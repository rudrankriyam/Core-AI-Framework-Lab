# Copyright 3D-Speaker (https://github.com/modelscope/3D-Speaker).
# Licensed under the Apache License, Version 2.0.
#
# Modified by Core AI Framework Lab to add converter-safe pooling, fold the
# final inference batch normalization, and expose a normalized embedding.

"""Core AI-compatible CAM++ speaker embedding model.

The architecture is adapted from the Apache-2.0 3D-Speaker implementation:
https://github.com/modelscope/3D-Speaker
"""

from collections import OrderedDict
from pathlib import Path

import torch
import torch.nn.functional as F
from torch import nn

FEATURE_BINS = 80
DEFAULT_FRAME_COUNT = 600
EMBEDDING_DIMENSION = 192
SEGMENT_FRAME_COUNT = 100
SOURCE_MODEL_PARAMETER_COUNT = 6_848_544
CONVERTED_MODEL_PARAMETER_COUNT = 6_848_736


def nonlinear_layers(config: str, channels: int) -> nn.Sequential:
    result = nn.Sequential()
    for name in config.split("-"):
        if name == "relu":
            result.add_module("relu", nn.ReLU(inplace=True))
        elif name == "batchnorm":
            result.add_module("batchnorm", nn.BatchNorm1d(channels))
        elif name == "batchnorm_":
            result.add_module(
                "batchnorm",
                nn.BatchNorm1d(channels, affine=False),
            )
        else:
            raise ValueError(f"Unsupported nonlinear layer: {name}")
    return result


class ReferenceStatisticsPooling(nn.Module):
    """The upstream CAM++ temporal mean and unbiased standard deviation."""

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        mean = value.mean(dim=-1)
        standard_deviation = value.std(dim=-1, unbiased=True)
        return torch.cat((mean, standard_deviation), dim=-1)


class CoreAIStatisticsPooling(nn.Module):
    """Equivalent pooling without unsupported ``aten.var.correction``."""

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        mean = value.mean(dim=-1)
        centered = value - mean.unsqueeze(-1)
        variance = (centered * centered).sum(dim=-1) / (value.shape[-1] - 1)
        standard_deviation = torch.sqrt(torch.clamp(variance, min=0))
        return torch.cat((mean, standard_deviation), dim=-1)


class ReferenceSegmentPooling(nn.Module):
    """The upstream ceil-mode average pooling expanded to the input length."""

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        pooled = F.avg_pool1d(
            value,
            kernel_size=SEGMENT_FRAME_COUNT,
            stride=SEGMENT_FRAME_COUNT,
            ceil_mode=True,
        )
        shape = pooled.shape
        return (
            pooled.unsqueeze(-1)
            .expand(*shape, SEGMENT_FRAME_COUNT)
            .reshape(*shape[:-1], -1)[..., : value.shape[-1]]
        )


class CoreAISegmentPooling(nn.Module):
    """Static equivalent of CAM++ segment pooling using supported reductions."""

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        batch, channels, frames = value.shape
        segment_count = frames // SEGMENT_FRAME_COUNT
        pooled = value.reshape(
            batch,
            channels,
            segment_count,
            SEGMENT_FRAME_COUNT,
        ).mean(dim=-1)
        return (
            pooled.unsqueeze(-1)
            .expand(batch, channels, segment_count, SEGMENT_FRAME_COUNT)
            .reshape(batch, channels, frames)
        )


class TDNNLayer(nn.Module):
    def __init__(
        self,
        input_channels: int,
        output_channels: int,
        kernel_size: int,
        stride: int = 1,
        padding: int = 0,
        dilation: int = 1,
        bias: bool = False,
        config: str = "batchnorm-relu",
    ) -> None:
        super().__init__()
        if padding < 0:
            if kernel_size % 2 != 1:
                raise ValueError("Negative padding requires an odd kernel size")
            padding = (kernel_size - 1) // 2 * dilation
        self.linear = nn.Conv1d(
            input_channels,
            output_channels,
            kernel_size,
            stride=stride,
            padding=padding,
            dilation=dilation,
            bias=bias,
        )
        self.nonlinear = nonlinear_layers(config, output_channels)

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        return self.nonlinear(self.linear(value))


class CAMLayer(nn.Module):
    def __init__(
        self,
        batch_norm_channels: int,
        output_channels: int,
        kernel_size: int,
        stride: int,
        padding: int,
        dilation: int,
        bias: bool,
        coreai_compatible: bool,
        reduction: int = 2,
    ) -> None:
        super().__init__()
        self.linear_local = nn.Conv1d(
            batch_norm_channels,
            output_channels,
            kernel_size,
            stride=stride,
            padding=padding,
            dilation=dilation,
            bias=bias,
        )
        self.linear1 = nn.Conv1d(
            batch_norm_channels,
            batch_norm_channels // reduction,
            1,
        )
        self.relu = nn.ReLU(inplace=True)
        self.linear2 = nn.Conv1d(
            batch_norm_channels // reduction,
            output_channels,
            1,
        )
        self.sigmoid = nn.Sigmoid()
        self.segment_pool = (
            CoreAISegmentPooling()
            if coreai_compatible
            else ReferenceSegmentPooling()
        )

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        local = self.linear_local(value)
        context = value.mean(dim=-1, keepdim=True) + self.segment_pool(value)
        attention = self.sigmoid(self.linear2(self.relu(self.linear1(context))))
        return local * attention


class CAMDenseTDNNLayer(nn.Module):
    def __init__(
        self,
        input_channels: int,
        output_channels: int,
        batch_norm_channels: int,
        kernel_size: int,
        dilation: int,
        config: str,
        coreai_compatible: bool,
    ) -> None:
        super().__init__()
        padding = (kernel_size - 1) // 2 * dilation
        self.nonlinear1 = nonlinear_layers(config, input_channels)
        self.linear1 = nn.Conv1d(
            input_channels,
            batch_norm_channels,
            1,
            bias=False,
        )
        self.nonlinear2 = nonlinear_layers(config, batch_norm_channels)
        self.cam_layer = CAMLayer(
            batch_norm_channels,
            output_channels,
            kernel_size,
            stride=1,
            padding=padding,
            dilation=dilation,
            bias=False,
            coreai_compatible=coreai_compatible,
        )

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        value = self.linear1(self.nonlinear1(value))
        return self.cam_layer(self.nonlinear2(value))


class CAMDenseTDNNBlock(nn.ModuleList):
    def __init__(
        self,
        layer_count: int,
        input_channels: int,
        output_channels: int,
        batch_norm_channels: int,
        kernel_size: int,
        dilation: int,
        config: str,
        coreai_compatible: bool,
    ) -> None:
        super().__init__()
        for index in range(layer_count):
            layer = CAMDenseTDNNLayer(
                input_channels + index * output_channels,
                output_channels,
                batch_norm_channels,
                kernel_size,
                dilation,
                config,
                coreai_compatible,
            )
            self.add_module(f"tdnnd{index + 1}", layer)

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        for layer in self:
            value = torch.cat((value, layer(value)), dim=1)
        return value


class TransitLayer(nn.Module):
    def __init__(
        self,
        input_channels: int,
        output_channels: int,
        config: str,
    ) -> None:
        super().__init__()
        self.nonlinear = nonlinear_layers(config, input_channels)
        self.linear = nn.Conv1d(
            input_channels,
            output_channels,
            1,
            bias=False,
        )

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        return self.linear(self.nonlinear(value))


class DenseLayer(nn.Module):
    def __init__(self, input_channels: int, output_channels: int) -> None:
        super().__init__()
        self.linear = nn.Conv1d(
            input_channels,
            output_channels,
            1,
            bias=False,
        )
        self.nonlinear = nonlinear_layers("batchnorm_", output_channels)

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        if value.ndim == 2:
            value = self.linear(value.unsqueeze(dim=-1)).squeeze(dim=-1)
        else:
            value = self.linear(value)
        return self.nonlinear(value)


class BasicResBlock(nn.Module):
    expansion = 1

    def __init__(
        self,
        input_channels: int,
        channels: int,
        stride: int = 1,
    ) -> None:
        super().__init__()
        self.conv1 = nn.Conv2d(
            input_channels,
            channels,
            kernel_size=3,
            stride=(stride, 1),
            padding=1,
            bias=False,
        )
        self.bn1 = nn.BatchNorm2d(channels)
        self.conv2 = nn.Conv2d(
            channels,
            channels,
            kernel_size=3,
            stride=1,
            padding=1,
            bias=False,
        )
        self.bn2 = nn.BatchNorm2d(channels)
        if stride != 1 or input_channels != channels:
            self.shortcut = nn.Sequential(
                nn.Conv2d(
                    input_channels,
                    channels,
                    kernel_size=1,
                    stride=(stride, 1),
                    bias=False,
                ),
                nn.BatchNorm2d(channels),
            )
        else:
            self.shortcut = nn.Sequential()

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        output = F.relu(self.bn1(self.conv1(value)))
        output = self.bn2(self.conv2(output))
        return F.relu(output + self.shortcut(value))


class FCM(nn.Module):
    def __init__(self, feature_bins: int = FEATURE_BINS) -> None:
        super().__init__()
        self.input_channels = 32
        self.conv1 = nn.Conv2d(
            1,
            32,
            kernel_size=3,
            stride=1,
            padding=1,
            bias=False,
        )
        self.bn1 = nn.BatchNorm2d(32)
        self.layer1 = self.make_layer(32, block_count=2, stride=2)
        self.layer2 = self.make_layer(32, block_count=2, stride=2)
        self.conv2 = nn.Conv2d(
            32,
            32,
            kernel_size=3,
            stride=(2, 1),
            padding=1,
            bias=False,
        )
        self.bn2 = nn.BatchNorm2d(32)
        self.out_channels = 32 * (feature_bins // 8)

    def make_layer(
        self,
        channels: int,
        block_count: int,
        stride: int,
    ) -> nn.Sequential:
        strides = [stride] + [1] * (block_count - 1)
        blocks: list[nn.Module] = []
        for block_stride in strides:
            blocks.append(
                BasicResBlock(
                    self.input_channels,
                    channels,
                    block_stride,
                )
            )
            self.input_channels = channels
        return nn.Sequential(*blocks)

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        output = value.unsqueeze(1)
        output = F.relu(self.bn1(self.conv1(output)))
        output = self.layer1(output)
        output = self.layer2(output)
        output = F.relu(self.bn2(self.conv2(output)))
        shape = output.shape
        return output.reshape(shape[0], shape[1] * shape[2], shape[3])


class CAMPPlus(nn.Module):
    """The 6.85M-parameter Apache-2.0 CAM++ checkpoint architecture."""

    def __init__(self, coreai_compatible: bool) -> None:
        super().__init__()
        growth_rate = 32
        batch_norm_channels = 4 * growth_rate
        config = "batchnorm-relu"

        self.head = FCM()
        channels = self.head.out_channels
        self.xvector = nn.Sequential(
            OrderedDict(
                [
                    (
                        "tdnn",
                        TDNNLayer(
                            channels,
                            128,
                            5,
                            stride=2,
                            padding=-1,
                            config=config,
                        ),
                    )
                ]
            )
        )
        channels = 128
        for index, (layer_count, kernel_size, dilation) in enumerate(
            zip((12, 24, 16), (3, 3, 3), (1, 2, 2)),
            start=1,
        ):
            block = CAMDenseTDNNBlock(
                layer_count,
                channels,
                growth_rate,
                batch_norm_channels,
                kernel_size,
                dilation,
                config,
                coreai_compatible,
            )
            self.xvector.add_module(f"block{index}", block)
            channels += layer_count * growth_rate
            self.xvector.add_module(
                f"transit{index}",
                TransitLayer(channels, channels // 2, config),
            )
            channels //= 2

        self.xvector.add_module(
            "out_nonlinear",
            nonlinear_layers(config, channels),
        )
        self.xvector.add_module(
            "stats",
            CoreAIStatisticsPooling()
            if coreai_compatible
            else ReferenceStatisticsPooling(),
        )
        self.xvector.add_module(
            "dense",
            DenseLayer(channels * 2, EMBEDDING_DIMENSION),
        )

    def forward(self, features: torch.Tensor) -> torch.Tensor:
        value = features.permute(0, 2, 1)
        return self.xvector(self.head(value))


class NormalizedSpeakerEmbeddingModel(nn.Module):
    def __init__(self, model: CAMPPlus) -> None:
        super().__init__()
        self.model = model

    def forward(self, features: torch.Tensor) -> torch.Tensor:
        embedding = self.model(features)
        magnitude = torch.sqrt(
            torch.sum(embedding * embedding, dim=1, keepdim=True)
        )
        return embedding / torch.clamp(magnitude, min=1e-12)


def fold_final_batch_norm(model: CAMPPlus) -> None:
    """Fold the final inference-only BatchNorm into its preceding Conv1d."""

    dense = model.xvector.dense
    if not isinstance(dense, DenseLayer):
        raise TypeError("Unexpected CAM++ dense layer")
    batch_norm = dense.nonlinear.batchnorm
    if not isinstance(batch_norm, nn.BatchNorm1d) or batch_norm.affine:
        raise TypeError("Expected the upstream non-affine final BatchNorm1d")

    scale = torch.rsqrt(batch_norm.running_var + batch_norm.eps)
    with torch.no_grad():
        dense.linear.weight.mul_(scale[:, None, None])
        dense.linear.bias = nn.Parameter(-batch_norm.running_mean * scale)
    dense.nonlinear = nn.Identity()


def load_checkpoint_model(
    checkpoint_path: Path,
    dtype: torch.dtype,
    coreai_compatible: bool,
    fold_batch_norm: bool = True,
) -> NormalizedSpeakerEmbeddingModel:
    model = CAMPPlus(coreai_compatible=coreai_compatible)
    state_dict = torch.load(
        checkpoint_path,
        map_location="cpu",
        weights_only=True,
    )
    model.load_state_dict(state_dict, strict=True)
    model.eval()
    if fold_batch_norm:
        fold_final_batch_norm(model)
    model.to(dtype)
    return NormalizedSpeakerEmbeddingModel(model).eval()
