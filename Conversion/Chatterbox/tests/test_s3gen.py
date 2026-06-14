from pathlib import Path

import torch
from huggingface_hub import hf_hub_download

from s3gen import load_s3gen_model, reference_inputs

REPO_ID = "ResembleAI/chatterbox-turbo"


def _paths() -> tuple[Path, Path]:
    return (
        Path(hf_hub_download(REPO_ID, "s3gen_meanflow.safetensors")),
        Path(hf_hub_download(REPO_ID, "conds.pt")),
    )


def test_coreai_s3gen_matches_original_convolutions() -> None:
    checkpoint_path, conditionals_path = _paths()
    source = load_s3gen_model(
        checkpoint_path,
        conditionals_path,
        dtype=torch.float32,
        coreai_compatible=False,
    )
    compatible = load_s3gen_model(
        checkpoint_path,
        conditionals_path,
        dtype=torch.float32,
        coreai_compatible=True,
    )
    speech_tokens, noise = reference_inputs(dtype=torch.float32)
    torch.manual_seed(8)
    noise.normal_()

    with torch.inference_mode():
        expected = source(speech_tokens, noise)
        actual = compatible(speech_tokens, noise)

    difference = (expected - actual).abs()
    assert difference.max().item() < 2e-4
    assert difference.mean().item() < 2e-5
