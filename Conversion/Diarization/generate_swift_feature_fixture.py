from __future__ import annotations

import argparse
from pathlib import Path

import torch

from model import DEFAULT_FRAME_COUNT
from validate import make_features, window_seconds


SAMPLE_RATE = 16_000
DEFAULT_OUTPUT = (
    Path(__file__).resolve().parents[2]
    / "CoreAILabTests"
    / "Fixtures"
    / "Diarization"
    / "CAMPPlusKaldiFeatures.float32"
)


def deterministic_waveform() -> torch.Tensor:
    sample_count = int(round(window_seconds(DEFAULT_FRAME_COUNT) * SAMPLE_RATE))
    indices = torch.arange(sample_count, dtype=torch.int64)
    samples = (
        (indices.remainder(97) - 48).to(torch.float32) / 256
        + (indices.remainder(53) - 26).to(torch.float32) / 512
    )
    return samples.unsqueeze(0)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate the deterministic Kaldi-fbank Swift parity fixture."
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    waveform = deterministic_waveform()
    features = make_features(
        waveform,
        sample_rate=SAMPLE_RATE,
        start=0,
        end=window_seconds(DEFAULT_FRAME_COUNT),
        frame_count=DEFAULT_FRAME_COUNT,
        dtype=torch.float32,
    )
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(features.squeeze(0).numpy().astype("<f4").tobytes())
    print(f"Wrote {features.numel()} Float32 values to {output}")


if __name__ == "__main__":
    main()
