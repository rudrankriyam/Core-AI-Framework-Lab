import argparse
import hashlib
import shutil
import time
from pathlib import Path

import torch
from coreai.runtime import AIModelAssetMetadata
from coreai_torch import TorchConverter, get_decomp_table
from huggingface_hub import hf_hub_download

from model import (
    CONVERTED_MODEL_PARAMETER_COUNT,
    DEFAULT_FRAME_COUNT,
    FEATURE_BINS,
    SOURCE_MODEL_PARAMETER_COUNT,
    load_checkpoint_model,
)

SOURCE_REPOSITORY = "funasr/campplus"
SOURCE_REVISION = "e4b6ede7ce16997aff4ae69fbca1f0175e2afede"
SOURCE_CHECKPOINT = "campplus_cn_common.bin"
SOURCE_CHECKPOINT_SHA256 = (
    "3388cf5fd3493c9ac9c69851d8e7a8badcfb4f3dc631020c4961371646d5ada8"
)
SOURCE_LICENSE = "Apache-2.0"


def torch_dtype(name: str) -> torch.dtype:
    return {
        "float16": torch.float16,
        "float32": torch.float32,
    }[name]


def default_output_path(dtype_name: str, frame_count: int) -> Path:
    return (
        Path(__file__).parent
        / "exports"
        / f"CAMPPlus192_{dtype_name}_{frame_count}f.aimodel"
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        while chunk := file.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def verify_checkpoint(checkpoint_path: Path) -> Path:
    actual = sha256_file(checkpoint_path)
    if actual != SOURCE_CHECKPOINT_SHA256:
        raise RuntimeError(
            "Checkpoint SHA-256 does not match the pinned Apache-2.0 artifact: "
            f"{actual}"
        )
    return checkpoint_path


def resolve_checkpoint(checkpoint_path: Path | None) -> Path:
    if checkpoint_path is not None:
        if not checkpoint_path.is_file():
            raise FileNotFoundError(checkpoint_path)
        return verify_checkpoint(checkpoint_path)
    return verify_checkpoint(
        Path(
            hf_hub_download(
                SOURCE_REPOSITORY,
                SOURCE_CHECKPOINT,
                revision=SOURCE_REVISION,
            )
        )
    )


def validate_static_frame_count(frame_count: int) -> None:
    # The first TDNN reduces the time axis by two. CAM++ then pools exact
    # 100-frame segments, so the exported static contract must preserve them.
    if frame_count < 200 or frame_count % 200 != 0:
        raise ValueError(
            "--frames must be an even multiple of 200 for CAM++ segment pooling"
        )


def validate_graph_rewrites(checkpoint_path: Path, frame_count: int) -> float:
    torch.manual_seed(19)
    value = torch.randn(
        (1, frame_count, FEATURE_BINS),
        dtype=torch.float32,
    )
    reference = load_checkpoint_model(
        checkpoint_path,
        dtype=torch.float32,
        coreai_compatible=False,
        fold_batch_norm=False,
    )
    source_parameter_count = sum(
        parameter.numel() for parameter in reference.parameters()
    )
    if source_parameter_count != SOURCE_MODEL_PARAMETER_COUNT:
        raise RuntimeError(
            f"Unexpected source parameter count: {source_parameter_count:,} "
            f"(expected {SOURCE_MODEL_PARAMETER_COUNT:,})"
        )
    converted = load_checkpoint_model(
        checkpoint_path,
        dtype=torch.float32,
        coreai_compatible=True,
    )
    with torch.inference_mode():
        expected = reference(value)
        actual = converted(value)
    cosine = torch.nn.functional.cosine_similarity(expected, actual).item()
    if cosine < 0.999999:
        raise RuntimeError(
            f"CAM++ graph rewrites failed parity: cosine={cosine:.9f}"
        )
    return cosine


def build_metadata(dtype_name: str, frame_count: int) -> AIModelAssetMetadata:
    metadata = AIModelAssetMetadata()
    metadata.author = "FunASR / 3D-Speaker; Core AI Framework Lab conversion"
    metadata.license = SOURCE_LICENSE
    metadata.model_description = (
        "CAM++ speaker embedding model. "
        f"Source revision: {SOURCE_REVISION}. "
        f"Checkpoint SHA-256: {SOURCE_CHECKPOINT_SHA256}. "
        f"Input: {dtype_name} [1, {frame_count}, {FEATURE_BINS}] log-Mel features. "
        f"Output: normalized {dtype_name} [1, 192] speaker embedding."
    )
    metadata.creation_date = int(time.time())
    return metadata


def export_model(args: argparse.Namespace) -> Path:
    validate_static_frame_count(args.frames)
    dtype = torch_dtype(args.dtype)
    checkpoint_path = resolve_checkpoint(args.checkpoint)
    rewrite_cosine = validate_graph_rewrites(checkpoint_path, args.frames)
    model = load_checkpoint_model(
        checkpoint_path,
        dtype=dtype,
        coreai_compatible=True,
    )
    parameter_count = sum(parameter.numel() for parameter in model.parameters())
    if parameter_count != CONVERTED_MODEL_PARAMETER_COUNT:
        raise RuntimeError(
            f"Unexpected parameter count: {parameter_count:,} "
            f"(expected {CONVERTED_MODEL_PARAMETER_COUNT:,})"
        )

    example = torch.zeros(
        (1, args.frames, FEATURE_BINS),
        dtype=dtype,
    )
    exported = torch.export.export(model, args=(example,))
    exported = exported.run_decompositions(get_decomp_table())
    converter = TorchConverter().add_exported_program(
        exported_program=exported,
        input_names=["features"],
        output_names=["embedding"],
    )
    program = converter.to_coreai()
    program.optimize()

    output_path = args.output or default_output_path(args.dtype, args.frames)
    if output_path.exists():
        if not args.overwrite:
            raise FileExistsError(
                f"{output_path} already exists. Pass --overwrite to replace it."
            )
        if output_path.is_dir():
            shutil.rmtree(output_path)
        else:
            output_path.unlink()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    program.save_asset(
        output_path,
        build_metadata(args.dtype, args.frames),
    )
    print(f"[OK] Source parameters: {SOURCE_MODEL_PARAMETER_COUNT:,}")
    print(f"[OK] Checkpoint SHA-256: {SOURCE_CHECKPOINT_SHA256}")
    print(f"[OK] Converted parameters after BatchNorm fold: {parameter_count:,}")
    print(f"[OK] Graph-rewrite cosine parity: {rewrite_cosine:.9f}")
    print(f"[OK] Wrote Core AI speaker embedding model to {output_path}")
    return output_path


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert Apache-2.0 CAM++ to a Core AI speaker embedding asset."
    )
    parser.add_argument(
        "--checkpoint",
        type=Path,
        help="Optional local CAM++ checkpoint; otherwise download the pinned source.",
    )
    parser.add_argument(
        "--dtype",
        choices=["float16", "float32"],
        default="float16",
    )
    parser.add_argument(
        "--frames",
        type=int,
        default=DEFAULT_FRAME_COUNT,
        help="Static count of 10 ms log-Mel frames; must be a multiple of 200.",
    )
    parser.add_argument("--output", type=Path)
    parser.add_argument("--overwrite", action="store_true")
    return parser


def main() -> None:
    args = build_argument_parser().parse_args()
    export_model(args)


if __name__ == "__main__":
    main()
