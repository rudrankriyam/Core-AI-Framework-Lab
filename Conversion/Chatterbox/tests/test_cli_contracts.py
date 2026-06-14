from types import SimpleNamespace

import numpy as np

from export import build_argument_parser as build_export_argument_parser
from runtime_validate import (
    build_argument_parser as build_runtime_validate_argument_parser,
)
from s3gen import S3GEN_GENERATED_MEL_FRAMES
from synthesize_coreai import tokenize_text
from t3 import T3_MAX_TEXT_TOKENS


def test_export_vocoder_defaults_to_s3gen_mel_length() -> None:
    args = build_export_argument_parser().parse_args(
        ["--mode", "export-vocoder"]
    )

    assert args.mel_frames == S3GEN_GENERATED_MEL_FRAMES


def test_runtime_validation_defaults_to_s3gen_mel_length() -> None:
    args = build_runtime_validate_argument_parser().parse_args([])

    assert args.mel_frames == S3GEN_GENERATED_MEL_FRAMES


def test_tokenizer_cannot_exceed_exported_prefill_limit() -> None:
    class RecordingTokenizer:
        def __init__(self) -> None:
            self.options = {}

        def __call__(self, text: str, **options):
            self.options = options
            return SimpleNamespace(
                input_ids=np.arange(
                    T3_MAX_TEXT_TOKENS + 44,
                    dtype=np.int64,
                ).reshape(1, -1)
            )

    tokenizer = RecordingTokenizer()
    tokens = tokenize_text(tokenizer, "A deliberately long prompt.")

    assert tokenizer.options["truncation"] is True
    assert tokenizer.options["max_length"] == T3_MAX_TEXT_TOKENS
    assert len(tokens) == T3_MAX_TEXT_TOKENS
    assert tokens[-1] == T3_MAX_TEXT_TOKENS - 1
