import copy

import pytest
import torch

from export import (
    SOURCE_CHECKPOINT_SHA256,
    SOURCE_LICENSE,
    SOURCE_REPOSITORY,
    build_argument_parser,
    sha256_file,
    validate_static_frame_count,
    verify_checkpoint,
)
from model import (
    DEFAULT_FRAME_COUNT,
    EMBEDDING_DIMENSION,
    FEATURE_BINS,
    SOURCE_MODEL_PARAMETER_COUNT,
    CAMPPlus,
    CoreAISegmentPooling,
    CoreAIStatisticsPooling,
    NormalizedSpeakerEmbeddingModel,
    ReferenceSegmentPooling,
    ReferenceStatisticsPooling,
    fold_final_batch_norm,
)
from validate import make_features, window_seconds


def test_coreai_statistics_pooling_matches_unbiased_standard_deviation() -> None:
    torch.manual_seed(7)
    value = torch.randn((2, 512, 300), dtype=torch.float32)

    with torch.inference_mode():
        expected = ReferenceStatisticsPooling()(value)
        actual = CoreAIStatisticsPooling()(value)

    assert torch.allclose(actual, expected, atol=1e-6, rtol=1e-5)


def test_coreai_segment_pooling_matches_upstream_for_static_contract() -> None:
    torch.manual_seed(11)
    value = torch.randn((2, 128, 300), dtype=torch.float32)

    with torch.inference_mode():
        expected = ReferenceSegmentPooling()(value)
        actual = CoreAISegmentPooling()(value)

    assert torch.allclose(actual, expected, atol=1e-6, rtol=1e-5)


def test_model_contract_and_parameter_count() -> None:
    source = CAMPPlus(coreai_compatible=True).eval()
    parameter_count = sum(parameter.numel() for parameter in source.parameters())
    model = NormalizedSpeakerEmbeddingModel(source)

    assert parameter_count == SOURCE_MODEL_PARAMETER_COUNT
    with torch.inference_mode():
        output = model(
            torch.randn((1, DEFAULT_FRAME_COUNT, FEATURE_BINS), dtype=torch.float32)
        )
    assert output.shape == (1, EMBEDDING_DIMENSION)
    assert torch.allclose(
        torch.linalg.vector_norm(output, dim=1),
        torch.ones(1),
        atol=1e-5,
        rtol=1e-5,
    )


def test_final_batch_norm_fold_preserves_inference() -> None:
    torch.manual_seed(17)
    reference = CAMPPlus(coreai_compatible=True).eval()
    folded = copy.deepcopy(reference)
    features = torch.randn((1, 200, FEATURE_BINS), dtype=torch.float32)

    fold_final_batch_norm(folded)
    with torch.inference_mode():
        expected = reference(features)
        actual = folded(features)

    assert torch.allclose(actual, expected, atol=1e-5, rtol=1e-5)


def test_window_duration_produces_exact_static_feature_count() -> None:
    sample_rate = 16_000
    duration = window_seconds(DEFAULT_FRAME_COUNT)
    waveform = torch.zeros((1, int(round(duration * sample_rate))))

    features = make_features(
        waveform,
        sample_rate=sample_rate,
        start=0,
        end=duration,
        frame_count=DEFAULT_FRAME_COUNT,
        dtype=torch.float32,
    )

    assert features.shape == (1, DEFAULT_FRAME_COUNT, FEATURE_BINS)


def test_export_defaults_to_apache_fp16_six_second_contract() -> None:
    args = build_argument_parser().parse_args([])

    assert SOURCE_REPOSITORY == "funasr/campplus"
    assert SOURCE_LICENSE == "Apache-2.0"
    assert args.dtype == "float16"
    assert args.frames == DEFAULT_FRAME_COUNT


def test_checkpoint_hash_prevents_false_license_metadata(tmp_path) -> None:
    checkpoint = tmp_path / "checkpoint.bin"
    checkpoint.write_bytes(b"not the pinned CAM++ checkpoint")

    assert sha256_file(checkpoint) != SOURCE_CHECKPOINT_SHA256
    with pytest.raises(RuntimeError, match="pinned Apache-2.0 artifact"):
        verify_checkpoint(checkpoint)


@pytest.mark.parametrize("frames", [200, 400, 600, 1_000])
def test_static_frame_count_accepts_complete_cam_segments(frames: int) -> None:
    validate_static_frame_count(frames)


@pytest.mark.parametrize("frames", [25, 199, 300, 399, 599, 601])
def test_static_frame_count_rejects_partial_cam_segments(frames: int) -> None:
    with pytest.raises(ValueError):
        validate_static_frame_count(frames)
