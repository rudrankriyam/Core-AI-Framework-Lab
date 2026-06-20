#!/usr/bin/env python3
"""Refresh the checked-in model catalog from apple/coreai-models."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import UTC, datetime
from pathlib import Path


def run(*arguments: str, cwd: Path | None = None) -> str:
    completed = subprocess.run(
        arguments,
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "repository",
        type=Path,
        help="Local checkout of https://github.com/apple/coreai-models",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("CoreAILab/Resources/AppleModels/apple-coreai-models.json"),
    )
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    repository = arguments.repository.resolve()
    registry = repository / "python/src/coreai_models/model_registry.py"
    if not registry.is_file():
        raise SystemExit(f"Model registry not found: {registry}")

    revision = run("git", "rev-parse", "HEAD", cwd=repository)
    models = json.loads(
        run(
            "python3",
            str(registry),
            "--list-models",
            "--json",
            cwd=repository,
        )
    )
    document = {
        "source_repository": "https://github.com/apple/coreai-models",
        "source_revision": revision,
        "generated_at": datetime.now(UTC).isoformat(),
        "models": models,
    }

    output = arguments.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(document, indent=2) + "\n")
    print(f"Wrote {len(models)} models from {revision} to {output}")


if __name__ == "__main__":
    main()
