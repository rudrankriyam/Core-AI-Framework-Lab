#!/usr/bin/env python3
from __future__ import annotations

import argparse
import plistlib
import subprocess
import tempfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


def run(command: list[str]) -> None:
    subprocess.run(command, cwd=REPOSITORY_ROOT, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build and run the opt-in CAM++ Core AI diarization integration test."
    )
    parser.add_argument(
        "--model",
        type=Path,
        help="Optional CAM++ asset override; defaults to the model bundled by the app.",
    )
    parser.add_argument("--media", type=Path, required=True)
    parser.add_argument("--minimum-speakers", type=int)
    parser.add_argument("--expected-pattern", help="Comma-separated anonymous IDs, such as 1,2,1,2")
    parser.add_argument(
        "--derived-data",
        type=Path,
        default=REPOSITORY_ROOT / "build" / "Xcode27",
    )
    args = parser.parse_args()

    model = args.model.resolve(strict=True) if args.model is not None else None
    media = args.media.resolve(strict=True)
    derived_data = args.derived_data.resolve()
    destination = "platform=macOS,arch=arm64"
    run(
        [
            "xcodebuild",
            "-project",
            "CoreAIFrameworkLab.xcodeproj",
            "-scheme",
            "CoreAILab",
            "-destination",
            destination,
            "-derivedDataPath",
            str(derived_data),
            "build-for-testing",
        ]
    )

    products = derived_data / "Build" / "Products"
    sdk_version = subprocess.run(
        ["xcrun", "--sdk", "macosx", "--show-sdk-version"],
        cwd=REPOSITORY_ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    source = products / f"CoreAILab_macosx{sdk_version}-arm64.xctestrun"
    with source.open("rb") as file:
        configuration = plistlib.load(file)
    test_target = configuration["CoreAILabTests"]
    environment = test_target.setdefault("EnvironmentVariables", {})
    if model is not None:
        environment["COREAI_CAMPPLUS_MODEL_PATH"] = str(model)
    environment["COREAI_DIARIZATION_MEDIA_PATH"] = str(media)
    if args.minimum_speakers is not None:
        environment["COREAI_DIARIZATION_MIN_SPEAKERS"] = str(args.minimum_speakers)
    if args.expected_pattern:
        environment["COREAI_DIARIZATION_EXPECTED_PATTERN"] = args.expected_pattern

    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            suffix=".xctestrun",
            prefix="CoreAILab-diarization-",
            dir=products,
            delete=False,
        ) as file:
            plistlib.dump(configuration, file)
            temporary_path = Path(file.name)
        run(
            [
                "xcodebuild",
                "-xctestrun",
                str(temporary_path),
                "-destination",
                destination,
                "-only-testing:CoreAILabTests/SpeakerDiarizationIntegrationTests",
                "test-without-building",
            ]
        )
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
