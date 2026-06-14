import argparse
import asyncio
import gc
import time
from pathlib import Path

import numpy as np
import torch
from coreai.runtime import (
    AIModel,
    ComputeUnitKind,
    NDArray,
    SpecializationOptions,
)
from huggingface_hub import hf_hub_download

from s3gen import (
    load_s3gen_model,
    reference_inputs as s3gen_reference_inputs,
)
from vocoder import (
    CoreAICompatibleVocoder,
    load_chatterbox_vocoder,
    reference_inputs as vocoder_reference_inputs,
)

REPO_ID = "ResembleAI/chatterbox-turbo"


def specialization_options(compute_unit: str) -> SpecializationOptions:
    if compute_unit == "gpu":
        return SpecializationOptions.from_preferred_compute_unit_kind(
            ComputeUnitKind.gpu()
        )
    if compute_unit == "cpu":
        return SpecializationOptions.cpu_only()
    return SpecializationOptions.default()


async def validate_s3gen(asset_path: Path, compute_unit: str) -> None:
    checkpoint_path = Path(
        hf_hub_download(REPO_ID, "s3gen_meanflow.safetensors")
    )
    conditionals_path = Path(hf_hub_download(REPO_ID, "conds.pt"))

    torch.manual_seed(29)
    speech_tokens, noise = s3gen_reference_inputs(dtype=torch.float16)
    speech_tokens.random_(0, 6561)
    noise.normal_()

    source = load_s3gen_model(
        checkpoint_path,
        conditionals_path,
        dtype=torch.float16,
        coreai_compatible=True,
    )
    with torch.inference_mode():
        expected = source(speech_tokens, noise).float().cpu().numpy()
    del source
    gc.collect()

    load_started = time.perf_counter()
    model = await AIModel.load(
        asset_path,
        specialization_options=specialization_options(compute_unit),
    )
    load_elapsed = time.perf_counter() - load_started
    function = model.load_function("main")

    run_started = time.perf_counter()
    outputs = await function(
        inputs={
            "speechTokens": NDArray(speech_tokens),
            "noise": NDArray(noise),
        }
    )
    run_elapsed = time.perf_counter() - run_started
    actual = outputs["mel"].numpy().astype(np.float32)

    difference = np.abs(expected - actual)
    print(f"[OK] Core AI functions: {model.function_names}")
    print(f"[OK] S3Gen output shape: {actual.shape}")
    print(f"[OK] Model load/specialization: {load_elapsed:.3f} seconds")
    print(f"[OK] S3Gen inference: {run_elapsed:.3f} seconds")
    print(f"[OK] S3Gen max error: {difference.max():.9g}")
    print(f"[OK] S3Gen mean error: {difference.mean():.9g}")
    print(
        "[OK] Mel statistics: "
        f"min={actual.min():.6f}, max={actual.max():.6f}, "
        f"mean={actual.mean():.6f}, std={actual.std():.6f}"
    )


async def validate_vocoder(
    asset_path: Path,
    compute_unit: str,
    mel_frames: int,
) -> None:
    checkpoint_path = Path(
        hf_hub_download(REPO_ID, "s3gen_meanflow.safetensors")
    )
    torch.manual_seed(41)
    speech_feat, phase, noise = vocoder_reference_inputs(
        mel_frames,
        dtype=torch.float16,
    )
    speech_feat.normal_(mean=-2.7, std=1.7)
    phase.uniform_(-torch.pi, torch.pi)
    phase[:, 0, :] = 0
    noise.normal_()

    source_vocoder = load_chatterbox_vocoder(
        checkpoint_path,
        dtype=torch.float16,
    )
    source = CoreAICompatibleVocoder(source_vocoder).eval().to(torch.float16)
    with torch.inference_mode():
        expected_waveform, expected_source = source(
            speech_feat,
            phase,
            noise,
        )
        expected_waveform = expected_waveform.float().cpu().numpy()
        expected_source = expected_source.float().cpu().numpy()
    del source, source_vocoder
    gc.collect()

    load_started = time.perf_counter()
    model = await AIModel.load(
        asset_path,
        specialization_options=specialization_options(compute_unit),
    )
    load_elapsed = time.perf_counter() - load_started
    function = model.load_function("vocoder")

    run_started = time.perf_counter()
    outputs = await function(
        inputs={
            "speech_feat": NDArray(speech_feat),
            "phase": NDArray(phase),
            "noise": NDArray(noise),
        }
    )
    run_elapsed = time.perf_counter() - run_started
    actual_waveform = outputs["waveform"].numpy().astype(np.float32)
    actual_source = outputs["source"].numpy().astype(np.float32)

    waveform_difference = np.abs(expected_waveform - actual_waveform)
    source_difference = np.abs(expected_source - actual_source)
    print(f"[OK] Core AI functions: {model.function_names}")
    print(f"[OK] Vocoder output shape: {actual_waveform.shape}")
    print(f"[OK] Model load/specialization: {load_elapsed:.3f} seconds")
    print(f"[OK] Vocoder inference: {run_elapsed:.3f} seconds")
    print(f"[OK] Waveform max error: {waveform_difference.max():.9g}")
    print(f"[OK] Waveform mean error: {waveform_difference.mean():.9g}")
    print(f"[OK] Source max error: {source_difference.max():.9g}")
    print(f"[OK] Source mean error: {source_difference.mean():.9g}")
    print(
        "[OK] Waveform statistics: "
        f"min={actual_waveform.min():.6f}, "
        f"max={actual_waveform.max():.6f}, "
        f"mean={actual_waveform.mean():.6f}, "
        f"std={actual_waveform.std():.6f}"
    )


async def run_validations(args: argparse.Namespace) -> None:
    if args.s3gen is not None:
        await validate_s3gen(args.s3gen, args.compute_unit)
    if args.vocoder is not None:
        await validate_vocoder(
            args.vocoder,
            args.compute_unit,
            args.mel_frames,
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run converted Chatterbox assets with the Core AI runtime."
    )
    parser.add_argument(
        "--s3gen",
        type=Path,
        help="Path to ChatterboxTurboS3Gen.aimodel.",
    )
    parser.add_argument(
        "--vocoder",
        type=Path,
        help="Path to ChatterboxTurboVocoder.aimodel.",
    )
    parser.add_argument("--mel-frames", type=int, default=256)
    parser.add_argument(
        "--compute-unit",
        choices=["default", "gpu", "cpu"],
        default="gpu",
    )
    args = parser.parse_args()

    if args.s3gen is None and args.vocoder is None:
        parser.error("Pass --s3gen PATH and/or --vocoder PATH")
    asyncio.run(run_validations(args))


if __name__ == "__main__":
    main()
