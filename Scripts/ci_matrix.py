#!/usr/bin/env python3
"""Validate and inspect the versioned Core AI CI verification matrix."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, Mapping, Sequence


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MATRIX_PATH = (
    REPOSITORY_ROOT / ".github/ci/verification-matrix.v1.json"
)

ROOT_KEYS = {"schemaVersion", "rolloutRequirements", "lanes"}
ROLLOUT_REQUIREMENT_KEYS = {
    "protectedBranchRef",
    "reviewedPullRequestsRequired",
    "directPushesRestricted",
    "actionsPolicy",
    "controlsRequiredBeforeRunnerProvisioning",
    "protectedEnvironments",
}
PROTECTED_ENVIRONMENT_KEYS = {
    "name",
    "requiredReviewers",
    "preventSelfReview",
    "deploymentBranchRef",
}
LANE_KEYS = {
    "id",
    "kind",
    "workflow",
    "executionBoundary",
    "triggers",
    "trustedRefs",
    "environment",
    "signingPolicy",
    "provisioningUpdatesAllowed",
    "externalModelAssets",
    "requiredSecrets",
    "evidence",
    "entries",
}
ENTRY_REQUIRED_KEYS = {
    "id",
    "runnerLabels",
    "platform",
    "architecture",
}
ENTRY_OPTIONAL_KEYS = {"pythonVersion", "xcodeMajor", "iosMinimum"}


class MatrixValidationError(ValueError):
    """The checked-in CI matrix does not satisfy the version-one contract."""


def _require_mapping(value: Any, context: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise MatrixValidationError(f"{context} must be an object")
    return value


def _require_exact_keys(
    value: Mapping[str, Any],
    *,
    required: set[str],
    optional: set[str] | None = None,
    context: str,
) -> None:
    optional = optional or set()
    missing = required - value.keys()
    unknown = value.keys() - required - optional
    if missing:
        raise MatrixValidationError(
            f"{context} is missing keys: {', '.join(sorted(missing))}"
        )
    if unknown:
        raise MatrixValidationError(
            f"{context} has unknown keys: {', '.join(sorted(unknown))}"
        )


def _require_string(value: Any, context: str) -> str:
    if not isinstance(value, str) or not value:
        raise MatrixValidationError(f"{context} must be a non-empty string")
    return value


def _require_string_list(value: Any, context: str) -> list[str]:
    if not isinstance(value, list) or not value:
        raise MatrixValidationError(f"{context} must be a non-empty string list")
    result: list[str] = []
    for index, item in enumerate(value):
        result.append(_require_string(item, f"{context}[{index}]"))
    if len(set(result)) != len(result):
        raise MatrixValidationError(f"{context} must not contain duplicates")
    return result


def _require_optional_string_list(value: Any, context: str) -> list[str]:
    if not isinstance(value, list):
        raise MatrixValidationError(f"{context} must be a string list")
    result: list[str] = []
    for index, item in enumerate(value):
        result.append(_require_string(item, f"{context}[{index}]"))
    if len(set(result)) != len(result):
        raise MatrixValidationError(f"{context} must not contain duplicates")
    return result


def _require_choice(value: Any, choices: set[str], context: str) -> str:
    result = _require_string(value, context)
    if result not in choices:
        raise MatrixValidationError(
            f"{context} must be one of: {', '.join(sorted(choices))}"
        )
    return result


def _require_enabled(value: Any, context: str) -> None:
    if value is not True:
        raise MatrixValidationError(f"{context} must be true")


def _workflow_declares_environment(workflow_path: Path, environment: str) -> bool:
    pattern = (
        rf"^[ \t]+environment:[ \t]*{re.escape(environment)}[ \t]*(?:#.*)?$"
    )
    return (
        re.search(pattern, workflow_path.read_text(), flags=re.MULTILINE)
        is not None
    )


def load_matrix(path: Path = DEFAULT_MATRIX_PATH) -> Mapping[str, Any]:
    try:
        document = json.loads(path.read_text())
    except FileNotFoundError as error:
        raise MatrixValidationError(f"matrix does not exist: {path}") from error
    except json.JSONDecodeError as error:
        raise MatrixValidationError(f"matrix is not valid JSON: {error}") from error
    return _require_mapping(document, "matrix")


def validate_matrix(
    document: Mapping[str, Any],
    *,
    repository_root: Path = REPOSITORY_ROOT,
) -> None:
    _require_exact_keys(document, required=ROOT_KEYS, context="matrix")
    if document["schemaVersion"] != 1:
        raise MatrixValidationError("matrix.schemaVersion must equal 1")

    rollout = _require_mapping(
        document["rolloutRequirements"], "matrix.rolloutRequirements"
    )
    _require_exact_keys(
        rollout,
        required=ROLLOUT_REQUIREMENT_KEYS,
        context="matrix.rolloutRequirements",
    )
    protected_branch_ref = _require_string(
        rollout["protectedBranchRef"],
        "matrix.rolloutRequirements.protectedBranchRef",
    )
    if protected_branch_ref != "refs/heads/main":
        raise MatrixValidationError(
            "matrix.rolloutRequirements.protectedBranchRef must equal refs/heads/main"
        )
    for requirement in (
        "reviewedPullRequestsRequired",
        "directPushesRestricted",
        "controlsRequiredBeforeRunnerProvisioning",
    ):
        _require_enabled(
            rollout[requirement], f"matrix.rolloutRequirements.{requirement}"
        )
    if rollout["actionsPolicy"] != "selected-actions-full-sha":
        raise MatrixValidationError(
            "matrix.rolloutRequirements.actionsPolicy must equal "
            "selected-actions-full-sha"
        )

    raw_environments = rollout["protectedEnvironments"]
    if not isinstance(raw_environments, list) or not raw_environments:
        raise MatrixValidationError(
            "matrix.rolloutRequirements.protectedEnvironments must be a non-empty list"
        )
    protected_environments: dict[str, int] = {}
    for environment_index, raw_environment in enumerate(raw_environments):
        context = (
            "matrix.rolloutRequirements.protectedEnvironments"
            f"[{environment_index}]"
        )
        environment = _require_mapping(raw_environment, context)
        _require_exact_keys(
            environment,
            required=PROTECTED_ENVIRONMENT_KEYS,
            context=context,
        )
        name = _require_string(environment["name"], f"{context}.name")
        if name in protected_environments:
            raise MatrixValidationError(f"duplicate protected environment: {name}")
        required_reviewers = environment["requiredReviewers"]
        if (
            not isinstance(required_reviewers, int)
            or isinstance(required_reviewers, bool)
            or required_reviewers < 1
        ):
            raise MatrixValidationError(
                f"{context}.requiredReviewers must be a positive integer"
            )
        _require_enabled(
            environment["preventSelfReview"], f"{context}.preventSelfReview"
        )
        if environment["deploymentBranchRef"] != protected_branch_ref:
            raise MatrixValidationError(
                f"{context}.deploymentBranchRef must equal {protected_branch_ref}"
            )
        protected_environments[name] = required_reviewers
    expected_environments = {"coreai-macos-hardware", "coreai-ios-hardware"}
    if set(protected_environments) != expected_environments:
        raise MatrixValidationError(
            "rollout requires protected coreai-macos-hardware and "
            "coreai-ios-hardware environments"
        )

    lanes = document["lanes"]
    if not isinstance(lanes, list) or not lanes:
        raise MatrixValidationError("matrix.lanes must be a non-empty list")

    lane_ids: set[str] = set()
    kinds: set[str] = set()
    entry_ids: set[str] = set()
    for lane_index, raw_lane in enumerate(lanes):
        context = f"matrix.lanes[{lane_index}]"
        lane = _require_mapping(raw_lane, context)
        _require_exact_keys(lane, required=LANE_KEYS, context=context)

        lane_id = _require_string(lane["id"], f"{context}.id")
        if lane_id in lane_ids:
            raise MatrixValidationError(f"duplicate lane id: {lane_id}")
        lane_ids.add(lane_id)

        kind = _require_choice(
            lane["kind"],
            {"hosted-software", "xcode-macos", "physical-ios"},
            f"{context}.kind",
        )
        if kind in kinds:
            raise MatrixValidationError(f"duplicate lane kind: {kind}")
        kinds.add(kind)

        workflow = _require_string(lane["workflow"], f"{context}.workflow")
        workflow_path = repository_root / workflow
        if workflow_path.parent != repository_root / ".github/workflows":
            raise MatrixValidationError(
                f"{context}.workflow must be directly below .github/workflows"
            )
        if not workflow_path.is_file():
            raise MatrixValidationError(f"workflow does not exist: {workflow}")

        boundary = _require_choice(
            lane["executionBoundary"],
            {"github-hosted", "self-hosted"},
            f"{context}.executionBoundary",
        )
        triggers = _require_string_list(lane["triggers"], f"{context}.triggers")
        trusted_refs = _require_string_list(
            lane["trustedRefs"], f"{context}.trustedRefs"
        )
        raw_environment = lane["environment"]
        environment = (
            None
            if raw_environment is None
            else _require_string(raw_environment, f"{context}.environment")
        )
        signing_policy = _require_choice(
            lane["signingPolicy"],
            {"disabled", "installed-assets-only"},
            f"{context}.signingPolicy",
        )
        if not isinstance(lane["provisioningUpdatesAllowed"], bool):
            raise MatrixValidationError(
                f"{context}.provisioningUpdatesAllowed must be a boolean"
            )
        if lane["provisioningUpdatesAllowed"]:
            raise MatrixValidationError(
                f"{context} must not allow provisioning updates"
            )
        external_assets = _require_choice(
            lane["externalModelAssets"],
            {"none", "repository-lfs", "fixture-only"},
            f"{context}.externalModelAssets",
        )
        required_secrets = _require_optional_string_list(
            lane["requiredSecrets"], f"{context}.requiredSecrets"
        )
        _require_string_list(lane["evidence"], f"{context}.evidence")

        entries = lane["entries"]
        if not isinstance(entries, list) or not entries:
            raise MatrixValidationError(f"{context}.entries must be non-empty")
        for entry_index, raw_entry in enumerate(entries):
            entry_context = f"{context}.entries[{entry_index}]"
            entry = _require_mapping(raw_entry, entry_context)
            _require_exact_keys(
                entry,
                required=ENTRY_REQUIRED_KEYS,
                optional=ENTRY_OPTIONAL_KEYS,
                context=entry_context,
            )
            entry_id = _require_string(entry["id"], f"{entry_context}.id")
            if entry_id in entry_ids:
                raise MatrixValidationError(f"duplicate entry id: {entry_id}")
            entry_ids.add(entry_id)
            labels = _require_string_list(
                entry["runnerLabels"], f"{entry_context}.runnerLabels"
            )
            _require_string(entry["platform"], f"{entry_context}.platform")
            _require_string(
                entry["architecture"], f"{entry_context}.architecture"
            )

            if boundary == "github-hosted":
                if labels != ["ubuntu-latest"]:
                    raise MatrixValidationError(
                        f"{entry_context} hosted runner must be ubuntu-latest"
                    )
                if "xcodeMajor" in entry or "iosMinimum" in entry:
                    raise MatrixValidationError(
                        f"{entry_context} hosted software cannot claim Apple hardware"
                    )
                if entry.get("pythonVersion") != "3.12":
                    raise MatrixValidationError(
                        f"{entry_context}.pythonVersion must equal 3.12"
                    )
            else:
                if "self-hosted" not in labels:
                    raise MatrixValidationError(
                        f"{entry_context} must include the self-hosted label"
                    )
                if entry.get("pythonVersion") != "3.12":
                    raise MatrixValidationError(
                        f"{entry_context}.pythonVersion must equal 3.12"
                    )
                if entry.get("xcodeMajor") != 27:
                    raise MatrixValidationError(
                        f"{entry_context}.xcodeMajor must equal 27"
                    )

        if kind == "hosted-software":
            if boundary != "github-hosted":
                raise MatrixValidationError("hosted-software must be github-hosted")
            if "pull_request" not in triggers or trusted_refs != ["*"]:
                raise MatrixValidationError(
                    "hosted-software must cover pull requests without a trust gate"
                )
            if signing_policy != "disabled" or external_assets != "none":
                raise MatrixValidationError(
                    "hosted-software must not use signing or model assets"
                )
            if required_secrets:
                raise MatrixValidationError("hosted-software must not require secrets")
            if environment is not None:
                raise MatrixValidationError(
                    "hosted-software must not use a protected environment"
                )
        else:
            if boundary != "self-hosted":
                raise MatrixValidationError(f"{kind} must be self-hosted")
            if "pull_request" in triggers:
                raise MatrixValidationError(
                    f"{kind} must never run for pull requests"
                )
            if trusted_refs != [protected_branch_ref]:
                raise MatrixValidationError(
                    f"{kind} must be restricted to {protected_branch_ref}"
                )
            expected_environment = {
                "xcode-macos": "coreai-macos-hardware",
                "physical-ios": "coreai-ios-hardware",
            }[kind]
            if environment != expected_environment:
                raise MatrixValidationError(
                    f"{kind} must use protected environment {expected_environment}"
                )
            if not _workflow_declares_environment(workflow_path, environment):
                raise MatrixValidationError(
                    f"{workflow} must declare environment: {environment}"
                )

        if kind == "xcode-macos":
            for entry in entries:
                labels = set(entry["runnerLabels"])
                if "coreai-macos-contracts" not in labels:
                    raise MatrixValidationError(
                        "xcode-macos entries require the dedicated macOS contract label"
                    )
                if "coreai-ios-device" in labels:
                    raise MatrixValidationError(
                        "xcode-macos entries must not target the signing runner"
                    )
            if signing_policy != "disabled" or external_assets != "repository-lfs":
                raise MatrixValidationError(
                    "xcode-macos requires disabled signing and repository LFS assets"
                )
        elif kind == "physical-ios":
            expected_labels = {"self-hosted", "coreai-xcode27", "coreai-ios-device"}
            for entry in entries:
                if not expected_labels.issubset(set(entry["runnerLabels"])):
                    raise MatrixValidationError(
                        "physical-ios entries require Xcode and device runner labels"
                    )
                if "coreai-macos-contracts" in entry["runnerLabels"]:
                    raise MatrixValidationError(
                        "physical-ios entries must not target the macOS contract runner"
                    )
                if entry.get("iosMinimum") != 27:
                    raise MatrixValidationError(
                        "physical-ios entries require iosMinimum 27"
                    )
            if triggers != ["workflow_dispatch"]:
                raise MatrixValidationError(
                    "physical-ios must only support workflow_dispatch"
                )
            if signing_policy != "installed-assets-only":
                raise MatrixValidationError(
                    "physical-ios may only use already-installed signing assets"
                )
            if external_assets != "fixture-only":
                raise MatrixValidationError(
                    "physical-ios must run only the checked-in fixture"
                )
            if required_secrets != ["COREAI_APPLE_TEAM_ID"]:
                raise MatrixValidationError(
                    "physical-ios requires only COREAI_APPLE_TEAM_ID"
                )

    expected_kinds = {"hosted-software", "xcode-macos", "physical-ios"}
    if kinds != expected_kinds:
        raise MatrixValidationError(
            "version-one matrix requires hosted, Xcode macOS, and physical iOS lanes"
        )


def github_matrix(document: Mapping[str, Any], lane_id: str) -> dict[str, Any]:
    validate_matrix(document)
    for lane in document["lanes"]:
        if lane["id"] == lane_id:
            return {"include": lane["entries"]}
    raise MatrixValidationError(f"unknown lane: {lane_id}")


def parse_arguments(arguments: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX_PATH)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate", help="validate the version-one contract")
    github_parser = subparsers.add_parser(
        "github-matrix", help="emit one lane as a GitHub Actions matrix"
    )
    github_parser.add_argument("--lane", required=True)
    github_parser.add_argument(
        "--github-output",
        type=Path,
        help="append matrix=<json> to this GitHub Actions output file",
    )
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    options = parse_arguments(arguments)
    document = load_matrix(options.matrix)
    if options.command == "validate":
        validate_matrix(document)
        print(f"Validated CI matrix schema version {document['schemaVersion']}")
        return 0

    matrix_json = json.dumps(
        github_matrix(document, options.lane),
        separators=(",", ":"),
    )
    line = f"matrix={matrix_json}\n"
    if options.github_output:
        with options.github_output.open("a") as output:
            output.write(line)
    else:
        print(line, end="")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except MatrixValidationError as error:
        raise SystemExit(f"CI matrix validation failed: {error}") from error
