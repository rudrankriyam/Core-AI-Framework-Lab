#!/usr/bin/env python3
"""Export a device-identifier-free summary from an xcresult bundle."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Mapping, Sequence


COUNT_KEYS = (
    "totalTestCount",
    "passedTests",
    "failedTests",
    "skippedTests",
    "expectedFailures",
)
EVIDENCE_KINDS = ("macos-contract-tests", "physical-ios-fixture")


class PublicSummaryError(RuntimeError):
    """The xcresult summary cannot be safely represented as public evidence."""


def _mapping(value: object) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def xcresult_summary_command(result_bundle: Path) -> list[str]:
    return [
        "xcrun",
        "xcresulttool",
        "get",
        "test-results",
        "summary",
        "--path",
        str(result_bundle),
        "--compact",
    ]


def load_xcresult_summary(result_bundle: Path) -> Mapping[str, Any]:
    completed = subprocess.run(
        xcresult_summary_command(result_bundle),
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise PublicSummaryError("xcresulttool could not read the result bundle")
    try:
        document = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise PublicSummaryError("xcresulttool returned invalid JSON") from error
    if not isinstance(document, Mapping):
        raise PublicSummaryError("xcresulttool returned a non-object summary")
    return document


def public_summary(
    document: Mapping[str, Any],
    *,
    evidence_kind: str,
    expected_platform: str,
) -> dict[str, object]:
    if evidence_kind not in EVIDENCE_KINDS:
        raise PublicSummaryError(f"Unsupported evidence kind: {evidence_kind}")

    result = document.get("result")
    if not isinstance(result, str) or not result:
        raise PublicSummaryError("xcresult summary has no result")

    counts: dict[str, int] = {}
    for key in COUNT_KEYS:
        value = document.get(key)
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise PublicSummaryError(f"xcresult summary has an invalid {key}")
        counts[key] = value

    configurations = document.get("devicesAndConfigurations")
    if not isinstance(configurations, list) or not configurations:
        raise PublicSummaryError("xcresult summary has no device configurations")
    platforms = sorted(
        {
            platform
            for item in configurations
            if isinstance(item, Mapping)
            for platform in [_mapping(item.get("device")).get("platform")]
            if isinstance(platform, str) and platform
        }
    )
    if expected_platform not in platforms:
        raise PublicSummaryError(
            f"xcresult summary does not contain the expected {expected_platform} platform"
        )

    return {
        "schemaVersion": 1,
        "evidenceKind": evidence_kind,
        "result": result,
        "counts": counts,
        "platforms": platforms,
        "identifiersRedacted": True,
    }


def parse_arguments(arguments: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write a public, identifier-free xcresult test summary."
    )
    parser.add_argument("--result-bundle", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--kind", required=True, choices=EVIDENCE_KINDS)
    parser.add_argument("--expected-platform", required=True)
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    options = parse_arguments(arguments)
    try:
        summary = public_summary(
            load_xcresult_summary(options.result_bundle),
            evidence_kind=options.kind,
            expected_platform=options.expected_platform,
        )
        options.output.parent.mkdir(parents=True, exist_ok=True)
        options.output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
        return 0
    except (OSError, PublicSummaryError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
