import types
from pathlib import Path

import torch
import torch.nn.functional as F
from safetensors import safe_open
from safetensors.torch import load_file
from torch import nn

from vocoder import replace_conv1d_modules

SPEAKER_ENCODER_PREFIX = "speaker_encoder."
SPEAKER_FBANK_BINS = 80
SPEAKER_FBANK_FRAMES = 200
VOICE_MEL_BINS = 40
VOICE_MEL_FRAMES = 160


class CoreAICompatibleVoiceEncoder(nn.Module):
    """VoiceEncoder forward path without data-dependent range assertions."""

    def __init__(self, voice_encoder: nn.Module) -> None:
        super().__init__()
        self.voice_encoder = voice_encoder

    def forward(self, mels: torch.Tensor) -> torch.Tensor:
        _, (hidden, _) = self.voice_encoder.lstm(mels)
        embedding = F.relu(self.voice_encoder.proj(hidden[-1]))
        magnitude = torch.sqrt(
            torch.sum(embedding * embedding, dim=1, keepdim=True)
        )
        return embedding / torch.clamp(magnitude, min=1e-12)


class CoreAIStatsPool(nn.Module):
    """Unbiased statistics pooling without aten.var.correction."""

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        mean = value.mean(dim=-1)
        centered = value - mean.unsqueeze(-1)
        variance = (centered * centered).sum(dim=-1) / (value.shape[-1] - 1)
        standard_deviation = torch.sqrt(torch.clamp(variance, min=0))
        return torch.cat((mean, standard_deviation), dim=-1)


class CoreAIBatchNorm1d(nn.Module):
    """Evaluation-mode BatchNorm1d folded into per-channel scale and bias."""

    def __init__(self, source: nn.BatchNorm1d) -> None:
        super().__init__()
        scale = torch.rsqrt(source.running_var + source.eps)
        if source.affine:
            scale = scale * source.weight
            offset = source.bias - source.running_mean * scale
        else:
            offset = -source.running_mean * scale
        self.register_buffer("scale", scale)
        self.register_buffer("offset", offset)

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        broadcast_shape = [1, self.scale.shape[0]]
        broadcast_shape.extend([1] * (value.ndim - 2))
        return (
            value * self.scale.reshape(broadcast_shape)
            + self.offset.reshape(broadcast_shape)
        )


def replace_batch_norm1d_modules(module: nn.Module) -> None:
    for name, child in list(module.named_children()):
        if isinstance(child, nn.BatchNorm1d):
            setattr(module, name, CoreAIBatchNorm1d(child))
        else:
            replace_batch_norm1d_modules(child)


def _single_segment_pooling(
    _module: nn.Module,
    value: torch.Tensor,
    seg_len: int = 100,
    stype: str = "avg",
) -> torch.Tensor:
    """Equivalent to CAMPPlus pooling when its internal sequence is 100 frames."""
    _ = seg_len
    _ = stype
    pooled = value.mean(dim=-1, keepdim=True)
    return pooled.expand_as(value)


def create_voice_encoder(checkpoint_path: Path) -> nn.Module:
    from chatterbox.models.voice_encoder.voice_encoder import VoiceEncoder

    model = VoiceEncoder().eval()
    model.load_state_dict(load_file(checkpoint_path), strict=True)
    return model


def create_speaker_encoder(
    checkpoint_path: Path,
    coreai_compatible: bool,
) -> nn.Module:
    from chatterbox.models.s3gen.xvector import CAMLayer, CAMPPlus

    model = CAMPPlus(memory_efficient=False).eval()
    with safe_open(checkpoint_path, framework="pt", device="cpu") as checkpoint:
        state_dict = {
            key.removeprefix(SPEAKER_ENCODER_PREFIX): checkpoint.get_tensor(key)
            for key in checkpoint.keys()
            if key.startswith(SPEAKER_ENCODER_PREFIX)
        }

    if not state_dict:
        raise ValueError(
            f"No {SPEAKER_ENCODER_PREFIX} tensors found in {checkpoint_path}"
        )

    model.load_state_dict(state_dict, strict=True)
    if coreai_compatible:
        model.xvector._modules["stats"] = CoreAIStatsPool()
        for module in model.modules():
            if isinstance(module, CAMLayer):
                module.seg_pooling = types.MethodType(
                    _single_segment_pooling,
                    module,
                )
        replace_batch_norm1d_modules(model)
        replace_conv1d_modules(model)
    return model


def voice_encoder_reference_inputs() -> tuple[torch.Tensor]:
    return (torch.zeros((1, VOICE_MEL_FRAMES, VOICE_MEL_BINS)),)


def speaker_encoder_reference_inputs() -> tuple[torch.Tensor]:
    return (torch.zeros((1, SPEAKER_FBANK_FRAMES, SPEAKER_FBANK_BINS)),)
