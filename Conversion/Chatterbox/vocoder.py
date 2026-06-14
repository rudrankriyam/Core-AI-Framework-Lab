import math
from pathlib import Path

import torch
import torch.nn.functional as F
from safetensors import safe_open
from torch import nn
from torch.nn.utils.parametrize import remove_parametrizations

MEL_CHANNELS = 80
SOURCE_CHANNELS = 9
SAMPLES_PER_MEL_FRAME = 480
VOCODER_PREFIX = "mel2wav."


class CoreAIELU(nn.Module):
    """ELU expressed with Core AI-supported primitive operations."""

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        return torch.where(value > 0, value, torch.exp(value) - 1)


class CoreAILastAxisConv1d(nn.Module):
    """Conv1d expressed as Conv2d with a trailing singleton dimension."""

    def __init__(self, source: nn.Conv1d) -> None:
        super().__init__()
        self.weight = source.weight
        self.bias = source.bias
        self.causal_padding = getattr(source, "causal_padding", None)
        self.stride = source.stride[0]
        self.padding = source.padding[0]
        self.dilation = source.dilation[0]
        self.groups = source.groups

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        if self.causal_padding is not None:
            value = F.pad(value, self.causal_padding)
        result = F.conv2d(
            value.unsqueeze(-1),
            self.weight.unsqueeze(-1),
            self.bias,
            stride=(self.stride, 1),
            padding=(self.padding, 0),
            dilation=(self.dilation, 1),
            groups=self.groups,
        )
        return result.squeeze(-1)


class CoreAILastAxisConvTranspose1d(nn.Module):
    """ConvTranspose1d expressed in the layout accepted by Xcode 27."""

    def __init__(self, source: nn.ConvTranspose1d) -> None:
        super().__init__()
        self.weight = source.weight
        self.bias = source.bias
        self.stride = source.stride[0]
        self.padding = source.padding[0]
        self.output_padding = source.output_padding[0]
        self.dilation = source.dilation[0]
        self.groups = source.groups

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        result = F.conv_transpose2d(
            value.unsqueeze(-1),
            self.weight.unsqueeze(-1),
            self.bias,
            stride=(self.stride, 1),
            padding=(self.padding, 0),
            output_padding=(self.output_padding, 0),
            groups=self.groups,
            dilation=(self.dilation, 1),
        )
        return result.squeeze(-1)


def replace_conv1d_modules(module: nn.Module) -> None:
    for name, child in list(module.named_children()):
        if isinstance(child, nn.Conv1d):
            setattr(module, name, CoreAILastAxisConv1d(child))
        elif isinstance(child, nn.ConvTranspose1d):
            setattr(module, name, CoreAILastAxisConvTranspose1d(child))
        else:
            replace_conv1d_modules(child)


def prepare_vocoder(vocoder: nn.Module) -> None:
    """Replace unsupported operators without changing learned behavior."""
    for index, module in enumerate(vocoder.f0_predictor.condnet):
        if isinstance(module, nn.ELU):
            vocoder.f0_predictor.condnet[index] = CoreAIELU()

    for module in vocoder.modules():
        parametrizations = getattr(module, "parametrizations", None)
        if parametrizations is not None and "weight" in parametrizations:
            remove_parametrizations(module, "weight", leave_parametrized=True)

    replace_conv1d_modules(vocoder)


class CoreAIFourier(nn.Module):
    """Fixed-filter STFT/ISTFT equivalent to Chatterbox's Torch FFT path."""

    def __init__(self, n_fft: int = 16, hop_length: int = 4) -> None:
        super().__init__()
        self.n_fft = n_fft
        self.hop_length = hop_length
        self.padding = n_fft // 2

        window = torch.hann_window(n_fft, periodic=True)
        sample = torch.arange(n_fft, dtype=torch.float32)
        frequency = torch.arange(n_fft // 2 + 1, dtype=torch.float32).unsqueeze(1)
        angle = 2 * math.pi * frequency * sample / n_fft

        stft_real = torch.cos(angle) * window
        stft_imaginary = -torch.sin(angle) * window

        inverse_scale = torch.full((n_fft // 2 + 1, 1), 2 / n_fft)
        inverse_scale[0] = 1 / n_fft
        inverse_scale[-1] = 1 / n_fft
        istft_real = torch.cos(angle) * window * inverse_scale
        istft_imaginary = -torch.sin(angle) * window * inverse_scale

        self.register_buffer("stft_real", stft_real.unsqueeze(1))
        self.register_buffer("stft_imaginary", stft_imaginary.unsqueeze(1))
        self.register_buffer("istft_real", istft_real.unsqueeze(1))
        self.register_buffer("istft_imaginary", istft_imaginary.unsqueeze(1))
        self.register_buffer("window_squared", window.square().reshape(1, 1, -1))

    def stft(self, waveform: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        left = waveform[..., 1 : self.padding + 1].flip(-1)
        right = waveform[..., -self.padding - 1 : -1].flip(-1)
        padded = torch.cat((left, waveform, right), dim=-1)
        real = F.conv2d(
            padded.unsqueeze(-1),
            self.stft_real.unsqueeze(-1),
            stride=(self.hop_length, 1),
        ).squeeze(-1)
        imaginary = F.conv2d(
            padded.unsqueeze(-1),
            self.stft_imaginary.unsqueeze(-1),
            stride=(self.hop_length, 1),
        ).squeeze(-1)
        return real, imaginary

    def istft(self, real: torch.Tensor, imaginary: torch.Tensor) -> torch.Tensor:
        waveform = F.conv_transpose2d(
            real.unsqueeze(-1),
            self.istft_real.unsqueeze(-1),
            stride=(self.hop_length, 1),
        ).squeeze(-1)
        waveform = waveform + F.conv_transpose2d(
            imaginary.unsqueeze(-1),
            self.istft_imaginary.unsqueeze(-1),
            stride=(self.hop_length, 1),
        ).squeeze(-1)

        envelope = F.conv_transpose2d(
            torch.ones_like(real[:, :1]).unsqueeze(-1),
            self.window_squared.unsqueeze(-1),
            stride=(self.hop_length, 1),
        ).squeeze(-1)
        waveform = waveform / torch.clamp(envelope, min=1e-11)
        return waveform[..., self.padding : -self.padding]


class CoreAICompatibleVocoder(nn.Module):
    """Chatterbox HiFT with randomness exposed as deterministic model inputs."""

    def __init__(self, vocoder: nn.Module) -> None:
        super().__init__()
        prepare_vocoder(vocoder)
        self.vocoder = vocoder
        self.fourier = CoreAIFourier(
            n_fft=vocoder.istft_params["n_fft"],
            hop_length=vocoder.istft_params["hop_len"],
        )
        self.upsample_scale = int(vocoder.f0_upsamp.scale_factor)

        harmonics = torch.arange(
            1,
            vocoder.nb_harmonics + 2,
            dtype=torch.float32,
        ).reshape(1, -1, 1)
        self.register_buffer("harmonics", harmonics)

    def build_source(
        self,
        f0: torch.Tensor,
        phase: torch.Tensor,
        noise: torch.Tensor,
    ) -> torch.Tensor:
        expanded = f0[:, None, :, None].expand(
            -1,
            1,
            -1,
            self.upsample_scale,
        )
        expanded = expanded.reshape(f0.shape[0], 1, -1)

        frequencies = expanded * self.harmonics / self.vocoder.sampling_rate
        cumulative = torch.cumsum(frequencies, dim=-1)
        fractional = cumulative - torch.floor(cumulative)
        sine_waves = self.vocoder.m_source.sine_amp * torch.sin(
            2 * math.pi * fractional + phase
        )

        voiced = (expanded > self.vocoder.m_source.l_sin_gen.voiced_threshold).to(
            dtype=expanded.dtype
        )
        noise_amplitude = (
            voiced * self.vocoder.m_source.noise_std
            + (1 - voiced) * self.vocoder.m_source.sine_amp / 3
        )
        sine_waves = sine_waves * voiced + noise_amplitude * noise
        source = self.vocoder.m_source.l_linear(sine_waves.transpose(1, 2))
        return self.vocoder.m_source.l_tanh(source).transpose(1, 2)

    def decode(self, speech_feat: torch.Tensor, source: torch.Tensor) -> torch.Tensor:
        source_real, source_imaginary = self.fourier.stft(source)
        source_spectrum = torch.cat((source_real, source_imaginary), dim=1)

        value = self.vocoder.conv_pre(speech_feat)
        for index in range(self.vocoder.num_upsamples):
            value = F.leaky_relu(value, self.vocoder.lrelu_slope)
            value = self.vocoder.ups[index](value)

            if index == self.vocoder.num_upsamples - 1:
                reflected = F.pad(value[..., 1:2], (0, value.shape[-1]))
                value = F.pad(value, (1, 0)) + reflected

            source_value = self.vocoder.source_downs[index](source_spectrum)
            source_value = self.vocoder.source_resblocks[index](source_value)
            value = value + source_value

            residual = self.vocoder.resblocks[
                index * self.vocoder.num_kernels
            ](value)
            for kernel_index in range(1, self.vocoder.num_kernels):
                residual = residual + self.vocoder.resblocks[
                    index * self.vocoder.num_kernels + kernel_index
                ](value)
            value = residual / self.vocoder.num_kernels

        value = F.leaky_relu(value)
        value = self.vocoder.conv_post(value)
        frequency_bins = self.vocoder.istft_params["n_fft"] // 2 + 1
        magnitude = torch.clamp(torch.exp(value[:, :frequency_bins]), max=1e2)
        phase = torch.sin(value[:, frequency_bins:])
        real = magnitude * torch.cos(phase)
        imaginary = magnitude * torch.sin(phase)
        waveform = self.fourier.istft(real, imaginary)
        return torch.clamp(
            waveform.squeeze(1),
            -self.vocoder.audio_limit,
            self.vocoder.audio_limit,
        )

    def forward(
        self,
        speech_feat: torch.Tensor,
        phase: torch.Tensor,
        noise: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        f0 = self.vocoder.f0_predictor(speech_feat)
        source = self.build_source(f0, phase, noise)
        waveform = self.decode(speech_feat, source)
        return waveform, source


def create_chatterbox_vocoder() -> nn.Module:
    from chatterbox.models.s3gen.const import S3GEN_SR
    from chatterbox.models.s3gen.f0_predictor import ConvRNNF0Predictor
    from chatterbox.models.s3gen.hifigan import HiFTGenerator

    return HiFTGenerator(
        sampling_rate=S3GEN_SR,
        upsample_rates=[8, 5, 3],
        upsample_kernel_sizes=[16, 11, 7],
        source_resblock_kernel_sizes=[7, 7, 11],
        source_resblock_dilation_sizes=[[1, 3, 5], [1, 3, 5], [1, 3, 5]],
        f0_predictor=ConvRNNF0Predictor(),
    )


def load_chatterbox_vocoder(
    checkpoint_path: Path,
    *,
    dtype: torch.dtype = torch.float32,
) -> nn.Module:
    vocoder = create_chatterbox_vocoder()
    with safe_open(checkpoint_path, framework="pt", device="cpu") as checkpoint:
        state_dict = {
            key.removeprefix(VOCODER_PREFIX): checkpoint.get_tensor(key)
            for key in checkpoint.keys()
            if key.startswith(VOCODER_PREFIX)
        }

    if not state_dict:
        raise ValueError(f"No {VOCODER_PREFIX} tensors found in {checkpoint_path}")

    vocoder.load_state_dict(state_dict, strict=True)
    return vocoder.eval().to(dtype=dtype)


def reference_inputs(
    mel_frames: int,
    *,
    dtype: torch.dtype = torch.float32,
) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    waveform_samples = mel_frames * SAMPLES_PER_MEL_FRAME
    return (
        torch.zeros((1, MEL_CHANNELS, mel_frames), dtype=dtype),
        torch.zeros((1, SOURCE_CHANNELS, 1), dtype=dtype),
        torch.zeros(
            (1, SOURCE_CHANNELS, waveform_samples),
            dtype=dtype,
        ),
    )
