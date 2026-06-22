from __future__ import annotations

import argparse
import wave
from pathlib import Path

import numpy as np


SAMPLE_RATE = 16_000
SILENCE_SECONDS = 1.0
LABELED_WINDOWS = (
    ("A", 324.104, 330.119),
    ("B", 84.472, 90.487),
    ("A", 794.632, 800.647),
    ("B", 95.864, 101.879),
)


def read_mono_pcm16(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as audio_file:
        if audio_file.getframerate() != SAMPLE_RATE:
            raise RuntimeError(f"Expected {SAMPLE_RATE} Hz AMI audio")
        if audio_file.getsampwidth() != 2:
            raise RuntimeError("Expected 16-bit PCM AMI audio")
        channel_count = audio_file.getnchannels()
        samples = np.frombuffer(
            audio_file.readframes(audio_file.getnframes()),
            dtype="<i2",
        ).reshape(-1, channel_count)
    if channel_count == 1:
        return samples[:, 0]
    return np.rint(samples.astype(np.float32).mean(axis=1)).astype("<i2")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create the labeled A-B-A-B AMI fixture used by the Swift integration test."
    )
    parser.add_argument("--audio", type=Path, required=True)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("/tmp/core-ai-diarization-ami-labeled.wav"),
    )
    args = parser.parse_args()

    source = read_mono_pcm16(args.audio.resolve())
    silence = np.zeros(round(SILENCE_SECONDS * SAMPLE_RATE), dtype="<i2")
    parts: list[np.ndarray] = []
    for index, (_, start, end) in enumerate(LABELED_WINDOWS):
        first_sample = round(start * SAMPLE_RATE)
        final_sample = round(end * SAMPLE_RATE)
        parts.append(source[first_sample:final_sample])
        if index < len(LABELED_WINDOWS) - 1:
            parts.append(silence)
    fixture = np.concatenate(parts)

    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output), "wb") as audio_file:
        audio_file.setnchannels(1)
        audio_file.setsampwidth(2)
        audio_file.setframerate(SAMPLE_RATE)
        audio_file.writeframes(fixture.astype("<i2", copy=False).tobytes())

    labels = " → ".join(label for label, _, _ in LABELED_WINDOWS)
    print(f"Wrote {len(fixture) / SAMPLE_RATE:.3f}s to {output}")
    print(f"Ground-truth source sequence: {labels}; expected anonymous pattern: 1,2,1,2")


if __name__ == "__main__":
    main()
