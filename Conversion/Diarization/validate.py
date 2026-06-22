import argparse
import asyncio
import json
import statistics
import time
import wave
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np
import torch
import torchaudio.compliance.kaldi as kaldi
from coreai.runtime import (
    AIModel,
    ComputeUnitKind,
    NDArray,
    SpecializationOptions,
)

from export import resolve_checkpoint, torch_dtype, validate_static_frame_count
from model import DEFAULT_FRAME_COUNT, FEATURE_BINS, load_checkpoint_model

AMI_SPEAKERS = ("A", "B", "C", "D")
FRAME_SHIFT_SECONDS = 0.01
FRAME_LENGTH_SECONDS = 0.025
WINDOW_MARGIN_SECONDS = 0.2
MIN_SAME_SPEAKER_WINDOW_GAP_SECONDS = 8.0
MIN_PARITY_COSINE = 0.999
MAX_RANDOM_ABSOLUTE_ERROR = 0.002
MIN_SMOKE_SEPARATION_MARGIN = 0.1


def specialization_options(compute_unit: str) -> SpecializationOptions:
    if compute_unit == "cpu":
        return SpecializationOptions.cpu_only()
    if compute_unit == "gpu":
        return SpecializationOptions.from_preferred_compute_unit_kind(
            ComputeUnitKind.gpu()
        )
    return SpecializationOptions.default()


def cosine(left: np.ndarray, right: np.ndarray) -> float:
    return float(
        np.dot(left, right) / (np.linalg.norm(left) * np.linalg.norm(right))
    )


def window_seconds(frame_count: int) -> float:
    return FRAME_LENGTH_SECONDS + (frame_count - 1) * FRAME_SHIFT_SECONDS


def load_ami_segments(
    segments_directory: Path,
) -> dict[str, list[tuple[float, float]]]:
    result: dict[str, list[tuple[float, float]]] = {}
    for speaker in AMI_SPEAKERS:
        path = segments_directory / f"ES2004a.{speaker}.segments.xml"
        root = ET.parse(path).getroot()
        result[speaker] = [
            (
                float(segment.attrib["transcriber_start"]),
                float(segment.attrib["transcriber_end"]),
            )
            for segment in root.findall("segment")
        ]
    return result


def overlaps_other_speaker(
    candidate: tuple[float, float],
    speaker: str,
    segments: dict[str, list[tuple[float, float]]],
) -> bool:
    start, end = candidate
    return any(
        other_start < end and other_end > start
        for other_speaker, intervals in segments.items()
        if other_speaker != speaker
        for other_start, other_end in intervals
    )


def select_ami_windows(
    segments: dict[str, list[tuple[float, float]]],
    duration: float,
) -> list[tuple[str, float, float]]:
    selected: list[tuple[str, float, float]] = []
    for speaker, intervals in segments.items():
        speaker_windows: list[tuple[str, float, float]] = []
        for segment_start, segment_end in intervals:
            start = segment_start + WINDOW_MARGIN_SECONDS
            end = start + duration
            while end <= segment_end - WINDOW_MARGIN_SECONDS:
                candidate = (start, end)
                if not overlaps_other_speaker(candidate, speaker, segments):
                    if (
                        not speaker_windows
                        or start - speaker_windows[-1][2]
                        >= MIN_SAME_SPEAKER_WINDOW_GAP_SECONDS
                    ):
                        speaker_windows.append((speaker, start, end))
                        if len(speaker_windows) == 2:
                            break
                        start = end + MIN_SAME_SPEAKER_WINDOW_GAP_SECONDS
                        end = start + duration
                        continue
                start += 0.25
                end = start + duration
            if len(speaker_windows) == 2:
                break
        if len(speaker_windows) != 2:
            raise RuntimeError(
                f"Could not find two clean {duration:.2f}s windows for speaker {speaker}"
            )
        selected.extend(speaker_windows)
    return selected


def load_pcm_wav(path: Path) -> tuple[torch.Tensor, int]:
    with wave.open(str(path), "rb") as audio_file:
        sample_rate = audio_file.getframerate()
        channel_count = audio_file.getnchannels()
        sample_width = audio_file.getsampwidth()
        if sample_width != 2:
            raise RuntimeError("AMI validation expects 16-bit PCM WAV audio")
        samples = np.frombuffer(
            audio_file.readframes(audio_file.getnframes()),
            dtype="<i2",
        ).astype(np.float32) / 32768.0
    waveform = torch.from_numpy(samples.copy()).reshape(channel_count, -1)
    if channel_count != 1:
        waveform = waveform.mean(dim=0, keepdim=True)
    return waveform, sample_rate


def make_features(
    waveform: torch.Tensor,
    sample_rate: int,
    start: float,
    end: float,
    frame_count: int,
    dtype: torch.dtype,
) -> torch.Tensor:
    first_sample = int(round(start * sample_rate))
    final_sample = int(round(end * sample_rate))
    clip = waveform[:, first_sample:final_sample]
    features = kaldi.fbank(
        clip,
        num_mel_bins=FEATURE_BINS,
        frame_length=FRAME_LENGTH_SECONDS * 1_000,
        frame_shift=FRAME_SHIFT_SECONDS * 1_000,
        sample_frequency=sample_rate,
        window_type="povey",
        dither=0.0,
        snip_edges=True,
    )
    if features.shape != (frame_count, FEATURE_BINS):
        raise RuntimeError(
            f"Unexpected feature shape: {tuple(features.shape)}; "
            f"expected {(frame_count, FEATURE_BINS)}"
        )
    features = features - features.mean(dim=0, keepdim=True)
    return features.unsqueeze(0).to(dtype)


async def run_coreai(
    function,
    features: list[torch.Tensor],
) -> tuple[list[np.ndarray], list[float]]:
    embeddings: list[np.ndarray] = []
    run_times: list[float] = []
    for value in features:
        started = time.perf_counter()
        outputs = await function(inputs={"features": NDArray(value)})
        run_times.append(time.perf_counter() - started)
        embeddings.append(
            outputs["embedding"].numpy().astype(np.float32)[0]
        )
    return embeddings, run_times


def evaluate_identification(
    labels: list[str],
    embeddings: list[np.ndarray],
) -> dict[str, float | int]:
    enrollment_indices = {
        speaker: labels.index(speaker)
        for speaker in sorted(set(labels))
    }
    correct = 0
    same_scores: list[float] = []
    different_scores: list[float] = []
    for index, (label, query) in enumerate(zip(labels, embeddings)):
        if index == enrollment_indices[label]:
            continue
        scores = {
            speaker: cosine(embeddings[enrollment_index], query)
            for speaker, enrollment_index in enrollment_indices.items()
        }
        predicted = max(scores, key=scores.get)
        correct += int(predicted == label)

    for left in range(len(embeddings)):
        for right in range(left + 1, len(embeddings)):
            score = cosine(embeddings[left], embeddings[right])
            if labels[left] == labels[right]:
                same_scores.append(score)
            else:
                different_scores.append(score)

    return {
        "correct": correct,
        "queries": len(enrollment_indices),
        "same_min": min(same_scores),
        "same_mean": statistics.mean(same_scores),
        "different_max": max(different_scores),
        "different_mean": statistics.mean(different_scores),
        "separation_margin": min(same_scores) - max(different_scores),
    }


async def validate(args: argparse.Namespace) -> dict:
    dtype = torch_dtype(args.dtype)
    checkpoint_path = resolve_checkpoint(args.checkpoint)
    source = load_checkpoint_model(
        checkpoint_path,
        dtype=dtype,
        coreai_compatible=True,
    )
    coreai_model = await AIModel.load(
        args.asset,
        specialization_options=specialization_options(args.compute_unit),
    )
    function = coreai_model.load_function("main")

    torch.manual_seed(42)
    random_features = torch.randn(
        (1, args.frames, FEATURE_BINS),
        dtype=dtype,
    )
    with torch.inference_mode():
        random_expected = source(random_features).float().numpy()[0]
    random_actual, random_times = await run_coreai(function, [random_features])
    random_parity = cosine(random_expected, random_actual[0])
    random_max_absolute_error = float(
        np.max(np.abs(random_expected - random_actual[0]))
    )
    random_norm_error = abs(float(np.linalg.norm(random_actual[0])) - 1.0)
    if random_parity < MIN_PARITY_COSINE:
        raise RuntimeError(f"Random parity cosine failed: {random_parity:.9f}")
    if random_max_absolute_error > MAX_RANDOM_ABSOLUTE_ERROR:
        raise RuntimeError(
            "Random parity maximum absolute error failed: "
            f"{random_max_absolute_error:.9f}"
        )
    if random_norm_error > 1e-3:
        raise RuntimeError(f"Random output norm failed: {random_norm_error:.9f}")

    report: dict = {
        "asset": str(args.asset),
        "dtype": args.dtype,
        "frames": args.frames,
        "random_parity_cosine": random_parity,
        "random_max_absolute_error": random_max_absolute_error,
        "random_norm_error": random_norm_error,
        "random_run_seconds": random_times[0],
    }

    if args.ami_audio is not None and args.ami_segments is not None:
        segments = load_ami_segments(args.ami_segments)
        duration = window_seconds(args.frames)
        windows = select_ami_windows(segments, duration)
        waveform, sample_rate = load_pcm_wav(args.ami_audio)
        features = [
            make_features(
                waveform,
                sample_rate,
                start,
                end,
                frame_count=args.frames,
                dtype=dtype,
            )
            for _, start, end in windows
        ]
        labels = [speaker for speaker, _, _ in windows]
        with torch.inference_mode():
            expected = [source(value).float().numpy()[0] for value in features]
        actual, run_times = await run_coreai(function, features)
        parity = [
            cosine(expected_value, actual_value)
            for expected_value, actual_value in zip(expected, actual)
        ]
        identification = evaluate_identification(labels, actual)
        if min(parity) < MIN_PARITY_COSINE:
            raise RuntimeError(f"AMI parity cosine failed: {min(parity):.9f}")
        if identification["correct"] != identification["queries"]:
            raise RuntimeError(f"AMI identification failed: {identification}")
        if identification["separation_margin"] < MIN_SMOKE_SEPARATION_MARGIN:
            raise RuntimeError(f"AMI speaker separation margin failed: {identification}")
        report["ami"] = {
            "audio": str(args.ami_audio),
            "windows": [
                {"speaker": speaker, "start": start, "end": end}
                for speaker, start, end in windows
            ],
            "parity_cosine_min": min(parity),
            "first_run_seconds": run_times[0],
            "warm_median_seconds": statistics.median(run_times[1:]),
            "identification": identification,
        }

    if args.json_output is not None:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return report


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate Core AI CAM++ parity and optional AMI speaker recognition."
    )
    parser.add_argument("--asset", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path)
    parser.add_argument(
        "--dtype",
        choices=["float16", "float32"],
        default="float16",
    )
    parser.add_argument("--frames", type=int, default=DEFAULT_FRAME_COUNT)
    parser.add_argument(
        "--compute-unit",
        choices=["default", "gpu", "cpu"],
        default="default",
    )
    parser.add_argument("--ami-audio", type=Path)
    parser.add_argument("--ami-segments", type=Path)
    parser.add_argument("--json-output", type=Path)
    return parser


def main() -> None:
    args = build_argument_parser().parse_args()
    validate_static_frame_count(args.frames)
    if (args.ami_audio is None) != (args.ami_segments is None):
        raise ValueError("Pass both --ami-audio and --ami-segments, or neither")
    report = asyncio.run(validate(args))
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
