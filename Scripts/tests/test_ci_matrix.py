from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS_DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_DIRECTORY))

import ci_matrix  # noqa: E402


CHECKOUT_ACTION = "actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5"
SETUP_PYTHON_ACTION = (
    "actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065"
)
UPLOAD_ARTIFACT_ACTION = (
    "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"
)


class CIMatrixTests(unittest.TestCase):
    def setUp(self) -> None:
        self.document = ci_matrix.load_matrix()

    def test_checked_in_matrix_satisfies_version_one_contract(self) -> None:
        ci_matrix.validate_matrix(self.document)

        self.assertEqual(self.document["schemaVersion"], 1)
        rollout = self.document["rolloutRequirements"]
        self.assertEqual(rollout["protectedBranchRef"], "refs/heads/main")
        self.assertTrue(rollout["reviewedPullRequestsRequired"])
        self.assertTrue(rollout["directPushesRestricted"])
        self.assertTrue(rollout["controlsRequiredBeforeRunnerProvisioning"])
        self.assertEqual(
            {lane["id"] for lane in self.document["lanes"]},
            {"hosted-software", "xcode27-macos", "physical-ios27"},
        )

    def test_rollout_cannot_precede_branch_protection(self) -> None:
        for requirement in (
            "reviewedPullRequestsRequired",
            "directPushesRestricted",
            "controlsRequiredBeforeRunnerProvisioning",
        ):
            with self.subTest(requirement=requirement):
                invalid = copy.deepcopy(self.document)
                invalid["rolloutRequirements"][requirement] = False

                with self.assertRaisesRegex(
                    ci_matrix.MatrixValidationError,
                    f"{requirement} must be true",
                ):
                    ci_matrix.validate_matrix(invalid)

    def test_hardware_lanes_require_reviewer_protected_environments(self) -> None:
        environments = {
            item["name"]: item
            for item in self.document["rolloutRequirements"][
                "protectedEnvironments"
            ]
        }
        self.assertEqual(
            set(environments),
            {"coreai-macos-hardware", "coreai-ios-hardware"},
        )
        for environment in environments.values():
            self.assertEqual(environment["requiredReviewers"], 1)
            self.assertTrue(environment["preventSelfReview"])
            self.assertEqual(
                environment["deploymentBranchRef"], "refs/heads/main"
            )

        for lane in self.document["lanes"]:
            workflow = (ci_matrix.REPOSITORY_ROOT / lane["workflow"]).read_text()
            if lane["executionBoundary"] == "self-hosted":
                self.assertIn(f"environment: {lane['environment']}", workflow)
            else:
                self.assertIsNone(lane["environment"])

        invalid = copy.deepcopy(self.document)
        invalid["rolloutRequirements"]["protectedEnvironments"][0][
            "requiredReviewers"
        ] = 0
        with self.assertRaisesRegex(
            ci_matrix.MatrixValidationError,
            "requiredReviewers must be a positive integer",
        ):
            ci_matrix.validate_matrix(invalid)

        invalid = copy.deepcopy(self.document)
        macos = next(
            item for item in invalid["lanes"] if item["kind"] == "xcode-macos"
        )
        macos["environment"] = "coreai-ios-hardware"
        with self.assertRaisesRegex(
            ci_matrix.MatrixValidationError,
            "xcode-macos must use protected environment coreai-macos-hardware",
        ):
            ci_matrix.validate_matrix(invalid)

    def test_github_matrix_contains_only_selected_lane(self) -> None:
        matrix = ci_matrix.github_matrix(self.document, "xcode27-macos")

        self.assertEqual(len(matrix["include"]), 1)
        self.assertEqual(matrix["include"][0]["id"], "apple-silicon-xcode27")
        self.assertIn("self-hosted", matrix["include"][0]["runnerLabels"])

    def test_github_output_is_compact_single_line_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "github-output"
            exit_code = ci_matrix.main(
                [
                    "github-matrix",
                    "--lane",
                    "physical-ios27",
                    "--github-output",
                    str(output),
                ]
            )

            self.assertEqual(exit_code, 0)
            key, value = output.read_text().rstrip("\n").split("=", 1)
            self.assertEqual(key, "matrix")
            self.assertEqual(
                json.loads(value)["include"][0]["iosMinimum"],
                27,
            )

    def test_self_hosted_lane_cannot_run_pull_request_code(self) -> None:
        invalid = copy.deepcopy(self.document)
        lane = next(item for item in invalid["lanes"] if item["kind"] == "xcode-macos")
        lane["triggers"].append("pull_request")

        with self.assertRaisesRegex(
            ci_matrix.MatrixValidationError,
            "must never run for pull requests",
        ):
            ci_matrix.validate_matrix(invalid)

    def test_physical_lane_cannot_allow_provisioning_updates(self) -> None:
        invalid = copy.deepcopy(self.document)
        lane = next(item for item in invalid["lanes"] if item["kind"] == "physical-ios")
        lane["provisioningUpdatesAllowed"] = True

        with self.assertRaisesRegex(
            ci_matrix.MatrixValidationError,
            "must not allow provisioning updates",
        ):
            ci_matrix.validate_matrix(invalid)

    def test_hardware_lanes_require_distinct_runner_labels(self) -> None:
        invalid = copy.deepcopy(self.document)
        physical = next(
            item for item in invalid["lanes"] if item["kind"] == "physical-ios"
        )
        physical["entries"][0]["runnerLabels"].append("coreai-macos-contracts")

        with self.assertRaisesRegex(
            ci_matrix.MatrixValidationError,
            "must not target the macOS contract runner",
        ):
            ci_matrix.validate_matrix(invalid)

        invalid = copy.deepcopy(self.document)
        macos = next(
            item for item in invalid["lanes"] if item["kind"] == "xcode-macos"
        )
        macos["entries"][0]["runnerLabels"].remove("coreai-macos-contracts")

        with self.assertRaisesRegex(
            ci_matrix.MatrixValidationError,
            "dedicated macOS contract label",
        ):
            ci_matrix.validate_matrix(invalid)

    def test_hosted_lane_cannot_claim_xcode_or_hardware(self) -> None:
        invalid = copy.deepcopy(self.document)
        lane = next(
            item for item in invalid["lanes"] if item["kind"] == "hosted-software"
        )
        lane["entries"][0]["xcodeMajor"] = 27

        with self.assertRaisesRegex(
            ci_matrix.MatrixValidationError,
            "hosted software cannot claim Apple hardware",
        ):
            ci_matrix.validate_matrix(invalid)

    def test_physical_workflow_uses_hardened_device_harness(self) -> None:
        workflow = (
            ci_matrix.REPOSITORY_ROOT / ".github/workflows/physical-ios.yml"
        ).read_text()

        self.assertIn("Scripts/run_device_tests.py", workflow)
        self.assertIn(
            "git lfs pull --include='CoreAILabTests/Fixtures/**' --exclude=''",
            workflow,
        )
        self.assertIn("Unresolved fixture LFS pointers", workflow)
        self.assertIn("lfs: false", workflow)
        self.assertNotIn("lfs: true", workflow)
        self.assertNotIn("allowProvisioningUpdates", workflow)
        self.assertNotIn("allowProvisioningDeviceRegistration", workflow)

    def test_workflows_include_their_declared_runner_labels(self) -> None:
        for lane in self.document["lanes"]:
            workflow = (ci_matrix.REPOSITORY_ROOT / lane["workflow"]).read_text()
            for entry in lane["entries"]:
                for label in entry["runnerLabels"]:
                    with self.subTest(lane=lane["id"], label=label):
                        self.assertIn(label, workflow)

    def test_workflows_select_their_declared_python_runtime(self) -> None:
        for lane in self.document["lanes"]:
            workflow = (ci_matrix.REPOSITORY_ROOT / lane["workflow"]).read_text()
            for entry in lane["entries"]:
                python_version = entry.get("pythonVersion")
                if python_version is None:
                    continue

                with self.subTest(lane=lane["id"], python=python_version):
                    self.assertIn(SETUP_PYTHON_ACTION, workflow)
                    self.assertIn(python_version, workflow)

    def test_external_actions_are_pinned_to_reviewed_commits(self) -> None:
        for lane in self.document["lanes"]:
            workflow = (ci_matrix.REPOSITORY_ROOT / lane["workflow"]).read_text()

            with self.subTest(lane=lane["id"], action="checkout"):
                self.assertIn(CHECKOUT_ACTION, workflow)

            if any("pythonVersion" in entry for entry in lane["entries"]):
                with self.subTest(lane=lane["id"], action="setup-python"):
                    self.assertIn(SETUP_PYTHON_ACTION, workflow)

            if lane["executionBoundary"] == "self-hosted":
                with self.subTest(lane=lane["id"], action="upload-artifact"):
                    self.assertIn(UPLOAD_ARTIFACT_ACTION, workflow)

    def test_hardware_workflows_upload_only_identifier_free_evidence(self) -> None:
        for lane in self.document["lanes"]:
            if lane["executionBoundary"] != "self-hosted":
                continue
            workflow = (ci_matrix.REPOSITORY_ROOT / lane["workflow"]).read_text()

            with self.subTest(lane=lane["id"]):
                self.assertIn("Scripts/xcresult_public_summary.py", workflow)
                self.assertIn("identifier-free", workflow)
                self.assertNotIn("${{ env.RESULT_BUNDLE }}", workflow)
                self.assertNotIn("xcodebuild.log", workflow)


if __name__ == "__main__":
    unittest.main()
