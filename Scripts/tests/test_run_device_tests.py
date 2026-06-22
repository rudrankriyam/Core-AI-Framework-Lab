from __future__ import annotations

import sys
import json
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path


SCRIPTS_DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_DIRECTORY))

import run_device_tests as harness  # noqa: E402


IDENTITY_HASH = "A" * 40


def device_document(
    *,
    name: str = "Test iPhone",
    identifier: str = "COREDEVICE-ID",
    udid: str = "00008140-TEST",
    platform: str = "iOS",
    reality: str = "physical",
    os_version: str = "27.0",
    boot_state: str = "booted",
    tunnel_state: str = "connected",
) -> dict[str, object]:
    return {
        "identifier": identifier,
        "connectionProperties": {
            "pairingState": "paired",
            "tunnelState": tunnel_state,
        },
        "deviceProperties": {
            "name": name,
            "bootState": boot_state,
            "developerModeStatus": "enabled",
            "ddiServicesAvailable": True,
            "osVersionNumber": os_version,
        },
        "hardwareProperties": {
            "platform": platform,
            "reality": reality,
            "udid": udid,
            "productType": "iPhone18,1",
        },
    }


def payload(*devices: dict[str, object]) -> dict[str, object]:
    return {
        "info": {"outcome": "success"},
        "result": {"devices": list(devices)},
    }


def signing_profile(
    *,
    name: str = "Local wildcard",
    uuid: str = "PROFILE-UUID",
    team: str = "ABCDEFGHIJ",
    device: str = "00008140-TEST",
    application_identifier: str = "ABCDEFGHIJ.*",
    certificate_hash: str = IDENTITY_HASH,
) -> harness.SigningProfile:
    return harness.SigningProfile(
        path=Path(f"/profiles/{uuid}.mobileprovision"),
        name=name,
        uuid=uuid,
        team_identifiers=(team,),
        platforms=("iOS",),
        application_identifier=application_identifier,
        expiration_date=datetime(2028, 1, 1, tzinfo=UTC),
        provisioned_devices=frozenset({device}),
        permits_debugging=True,
        certificate_hashes=frozenset({certificate_hash}),
    )


class DeviceDiscoveryTests(unittest.TestCase):
    def test_selects_only_eligible_physical_device_and_uses_udid(self) -> None:
        documents = payload(
            device_document(
                name="Simulator",
                identifier="SIMULATOR-ID",
                udid="SIMULATOR-UDID",
                reality="simulated",
            ),
            device_document(),
        )

        selected = harness.select_device(
            harness.devices_from_document(documents),
            selector=None,
        )

        self.assertEqual(selected.identifier, "COREDEVICE-ID")
        self.assertEqual(selected.destination_identifier, "00008140-TEST")
        self.assertEqual(selected.model_identifier, "iPhone18,1")

    def test_selector_accepts_name_coredevice_identifier_or_udid(self) -> None:
        devices = harness.devices_from_document(payload(device_document()))

        for selector in ("Test iPhone", "COREDEVICE-ID", "00008140-TEST"):
            with self.subTest(selector=selector):
                self.assertEqual(
                    harness.select_device(devices, selector).destination_identifier,
                    "00008140-TEST",
                )

    def test_explicit_simulator_or_mac_is_rejected(self) -> None:
        for platform, reality in (("iOS", "simulated"), ("macOS", "physical")):
            with self.subTest(platform=platform, reality=reality):
                devices = harness.devices_from_document(
                    payload(
                        device_document(
                            identifier="BAD-ID",
                            platform=platform,
                            reality=reality,
                        )
                    )
                )
                with self.assertRaisesRegex(
                    harness.DeviceTestHarnessError,
                    "ineligible",
                ):
                    harness.select_device(devices, "BAD-ID")

    def test_old_or_disconnected_phone_is_rejected(self) -> None:
        for version, tunnel in (("26.5", "connected"), ("27.0", "disconnected")):
            with self.subTest(version=version, tunnel=tunnel):
                devices = harness.devices_from_document(
                    payload(device_document(os_version=version, tunnel_state=tunnel))
                )
                with self.assertRaises(harness.DeviceTestHarnessError):
                    harness.select_device(devices, None)

    def test_multiple_eligible_devices_require_explicit_selector(self) -> None:
        devices = harness.devices_from_document(
            payload(
                device_document(),
                device_document(
                    name="Second iPhone",
                    identifier="SECOND-ID",
                    udid="00008140-SECOND",
                ),
            )
        )

        with self.assertRaisesRegex(
            harness.DeviceTestHarnessError,
            "Multiple eligible physical devices",
        ):
            harness.select_device(devices, None)

    def test_devicectl_command_uses_supported_json_file_interface(self) -> None:
        command = harness.devicectl_command(Path("/tmp/devices.json"))

        self.assertEqual(
            command,
            [
                "xcrun",
                "devicectl",
                "list",
                "devices",
                "--quiet",
                "--json-output",
                "/tmp/devices.json",
            ],
        )

    def test_lock_state_command_uses_the_selected_physical_udid(self) -> None:
        command = harness.devicectl_lock_state_command(
            "00008140-TEST",
            Path("/tmp/lock-state.json"),
        )

        self.assertEqual(
            command,
            [
                "xcrun",
                "devicectl",
                "device",
                "info",
                "lockState",
                "--device",
                "00008140-TEST",
                "--quiet",
                "--json-output",
                "/tmp/lock-state.json",
            ],
        )

    def test_lock_state_must_definitively_report_unlocked(self) -> None:
        harness.validate_unlocked_device_document(
            {"result": {"passcodeRequired": False}}
        )

        with self.assertRaisesRegex(
            harness.DeviceTestHarnessError,
            "Unlock the selected iOS device",
        ):
            harness.validate_unlocked_device_document(
                {"result": {"passcodeRequired": True}}
            )

        with self.assertRaisesRegex(
            harness.DeviceTestHarnessError,
            "definitive unlocked device state",
        ):
            harness.validate_unlocked_device_document({"result": {}})


class SigningProfileTests(unittest.TestCase):
    def test_selects_local_wildcard_profile_covering_both_bundles(self) -> None:
        profile = signing_profile()

        selected = harness.select_signing_profile(
            [profile],
            selector=None,
            team_identifier="ABCDEFGHIJ",
            device_identifier="00008140-TEST",
            identity_hashes=frozenset({IDENTITY_HASH}),
            now=datetime(2027, 1, 1, tzinfo=UTC),
        )

        self.assertEqual(selected.uuid, "PROFILE-UUID")

    def test_rejects_profile_without_test_bundle_coverage(self) -> None:
        profile = signing_profile(
            application_identifier="ABCDEFGHIJ.com.rudrank.CoreAILab"
        )

        with self.assertRaisesRegex(
            harness.DeviceTestHarnessError,
            "CoreAILabTests",
        ):
            harness.select_signing_profile(
                [profile],
                selector=None,
                team_identifier="ABCDEFGHIJ",
                device_identifier="00008140-TEST",
                identity_hashes=frozenset({IDENTITY_HASH}),
                now=datetime(2027, 1, 1, tzinfo=UTC),
            )

    def test_multiple_eligible_profiles_require_explicit_selector(self) -> None:
        profiles = [
            signing_profile(name="First", uuid="FIRST"),
            signing_profile(name="Second", uuid="SECOND"),
        ]

        with self.assertRaisesRegex(
            harness.DeviceTestHarnessError,
            "Multiple eligible provisioning profiles",
        ):
            harness.select_signing_profile(
                profiles,
                selector=None,
                team_identifier="ABCDEFGHIJ",
                device_identifier="00008140-TEST",
                identity_hashes=frozenset({IDENTITY_HASH}),
                now=datetime(2027, 1, 1, tzinfo=UTC),
            )


class CommandConstructionTests(unittest.TestCase):
    def test_command_is_filtered_local_automatic_and_never_updates_provisioning(self) -> None:
        device = harness.Device.from_document(device_document())
        command = harness.xcodebuild_command(
            device=device,
            team_identifier="ABCDEFGHIJ",
            result_bundle=Path("/tmp/result.xcresult"),
            derived_data=Path("/tmp/DerivedData"),
        )

        self.assertIn("platform=iOS,id=00008140-TEST", command)
        self.assertIn("-only-testing:" + harness.REAL_FIXTURE_TEST, command)
        self.assertTrue(harness.REAL_FIXTURE_TEST.endswith("()"))
        self.assertIn("CODE_SIGN_STYLE=Automatic", command)
        self.assertIn("DEVELOPMENT_TEAM=ABCDEFGHIJ", command)
        self.assertIn("CODE_SIGN_IDENTITY=Apple Development", command)
        self.assertFalse(
            any(item.startswith("PROVISIONING_PROFILE=") for item in command)
        )
        self.assertIn("CODE_SIGNING_ALLOWED=YES", command)
        self.assertNotIn("-allowProvisioningUpdates", command)
        self.assertNotIn("-allowProvisioningDeviceRegistration", command)

    def test_xcresult_summary_is_json_native_test_summary_command(self) -> None:
        self.assertEqual(
            harness.xcresult_summary_command(Path("/tmp/result.xcresult")),
            [
                "xcrun",
                "xcresulttool",
                "get",
                "test-results",
                "summary",
                "--path",
                "/tmp/result.xcresult",
                "--compact",
            ],
        )

    def test_xcresult_requires_exactly_one_pass_on_the_selected_ios_device(self) -> None:
        summary = {
            "result": "Passed",
            "totalTestCount": 1,
            "passedTests": 1,
            "failedTests": 0,
            "skippedTests": 0,
            "expectedFailures": 0,
            "devicesAndConfigurations": [
                {
                    "device": {
                        "platform": "iOS",
                        "deviceId": "00008140-TEST",
                    },
                    "passedTests": 1,
                    "failedTests": 0,
                    "skippedTests": 0,
                    "expectedFailures": 0,
                }
            ],
        }

        harness.validate_xcresult_summary(
            summary,
            expected_device_identifier="00008140-TEST",
        )

    def test_xcresult_rejects_an_empty_filtered_run(self) -> None:
        summary = {
            "result": "Passed",
            "totalTestCount": 0,
            "passedTests": 0,
            "failedTests": 0,
            "skippedTests": 0,
            "expectedFailures": 0,
            "devicesAndConfigurations": [],
        }

        with self.assertRaisesRegex(
            harness.DeviceTestHarnessError,
            "exactly one passed fixture test",
        ):
            harness.validate_xcresult_summary(
                summary,
                expected_device_identifier="00008140-TEST",
            )

    def test_xcresult_rejects_a_different_or_non_ios_device(self) -> None:
        for platform, identifier in (
            ("macOS", "00008140-TEST"),
            ("iOS", "00008140-OTHER"),
        ):
            with self.subTest(platform=platform, identifier=identifier):
                summary = {
                    "result": "Passed",
                    "totalTestCount": 1,
                    "passedTests": 1,
                    "failedTests": 0,
                    "skippedTests": 0,
                    "expectedFailures": 0,
                    "devicesAndConfigurations": [
                        {
                            "device": {
                                "platform": platform,
                                "deviceId": identifier,
                            },
                            "passedTests": 1,
                            "failedTests": 0,
                            "skippedTests": 0,
                            "expectedFailures": 0,
                        }
                    ],
                }
                with self.assertRaisesRegex(
                    harness.DeviceTestHarnessError,
                    "selected physical iOS device",
                ):
                    harness.validate_xcresult_summary(
                        summary,
                        expected_device_identifier="00008140-TEST",
                    )


class DeviceEvidenceTests(unittest.TestCase):
    def test_directory_identity_rejects_a_symlinked_root(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            asset = root / "asset.aimodel"
            asset.mkdir()
            (asset / "model.bin").write_bytes(b"model")
            linked_root = root / "linked.aimodel"
            linked_root.symlink_to(asset, target_is_directory=True)

            with self.assertRaisesRegex(
                harness.DeviceTestHarnessError,
                "root must not be a symbolic link",
            ):
                harness.directory_identity(linked_root)

    def test_directory_identity_rejects_all_nested_symlink_forms(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            outside = root / "outside"
            outside.mkdir()
            (outside / "target.bin").write_bytes(b"outside")

            for name, target, is_directory in (
                ("file-link", outside / "target.bin", False),
                ("directory-link", outside, True),
                ("broken-link", root / "missing", False),
            ):
                with self.subTest(name=name):
                    asset = root / f"{name}.aimodel"
                    asset.mkdir()
                    (asset / "model.bin").write_bytes(b"model")
                    (asset / name).symlink_to(
                        target,
                        target_is_directory=is_directory,
                    )
                    with self.assertRaisesRegex(
                        harness.DeviceTestHarnessError,
                        "refuses symbolic links",
                    ):
                        harness.directory_identity(asset)

    def test_built_fixture_path_names_the_xctest_resource_tree(self) -> None:
        self.assertEqual(
            harness.built_fixture_asset(Path("/tmp/DerivedData")),
            Path(
                "/tmp/DerivedData/Build/Products/Debug-iphoneos/"
                "CoreAILab.app/PlugIns/CoreAILabTests.xctest/Fixtures/"
                "CoreAILabTensorFixture.aimodel"
            ),
        )

    def test_dry_run_evidence_is_explicitly_non_executed_and_unmeasured(self) -> None:
        evidence = harness.device_trial_evidence(
            run_mode="dryRun",
            device=harness.Device.from_document(device_document()),
            execution_succeeded=False,
            captured_at=datetime(2027, 1, 2, 3, 4, 5, tzinfo=UTC),
        )

        self.assertEqual(evidence["schemaVersion"], 1)
        self.assertEqual(evidence["runMode"], "dryRun")
        self.assertEqual(evidence["specialization"]["status"], "notRun")
        self.assertEqual(evidence["inference"]["status"], "notRun")
        self.assertEqual(evidence["latency"]["availability"], "unavailable")
        self.assertEqual(evidence["memory"]["availability"], "unavailable")
        self.assertEqual(evidence["energy"]["availability"], "unavailable")
        self.assertEqual(evidence["placement"]["availability"], "unavailable")
        self.assertEqual(evidence["placement"]["actualComputeUnits"], [])
        self.assertEqual(
            {check["result"] for check in evidence["neuralEngineCompatibilityChecks"]},
            {"notEvaluated"},
        )

    def test_physical_xctest_evidence_does_not_invent_metrics_or_placement(self) -> None:
        evidence = harness.device_trial_evidence(
            run_mode="physical",
            device=harness.Device.from_document(device_document()),
            execution_succeeded=True,
            captured_at=datetime(2027, 1, 2, 3, 4, 5, tzinfo=UTC),
        )

        self.assertEqual(evidence["specialization"]["status"], "succeeded")
        self.assertEqual(evidence["inference"]["status"], "succeeded")
        self.assertIsNone(evidence["specialization"]["durationMilliseconds"])
        self.assertEqual(evidence["latency"]["samplesMilliseconds"], [])
        self.assertEqual(evidence["thermal"]["started"], "unavailable")
        self.assertEqual(evidence["energy"]["availability"], "unavailable")
        self.assertEqual(evidence["placement"]["availability"], "unavailable")

    def test_failed_physical_attempt_records_no_unproven_stage_success(self) -> None:
        evidence = harness.device_trial_evidence(
            run_mode="physical",
            device=harness.Device.from_document(device_document()),
            execution_succeeded=False,
            captured_at=datetime(2027, 1, 2, 3, 4, 5, tzinfo=UTC),
        )

        self.assertEqual(evidence["specialization"]["status"], "notRun")
        self.assertEqual(evidence["inference"]["status"], "notRun")
        self.assertIn("not proven", evidence["specialization"]["detail"])
        self.assertIn("not proven", evidence["inference"]["detail"])

    def test_artifact_and_configuration_identities_are_stable_sha256(self) -> None:
        first = harness.device_trial_evidence(
            run_mode="dryRun",
            device=harness.Device.from_document(device_document()),
            execution_succeeded=False,
            captured_at=datetime(2027, 1, 2, tzinfo=UTC),
        )
        second = harness.device_trial_evidence(
            run_mode="dryRun",
            device=harness.Device.from_document(device_document()),
            execution_succeeded=False,
            captured_at=datetime(2027, 1, 3, tzinfo=UTC),
        )

        self.assertEqual(first["artifact"], second["artifact"])
        self.assertEqual(first["configuration"], second["configuration"])
        self.assertRegex(first["artifact"]["sha256Digest"], r"^[0-9a-f]{64}$")
        self.assertGreater(first["artifact"]["byteCount"], 0)
        self.assertRegex(
            first["configuration"]["sha256Digest"],
            r"^[0-9a-f]{64}$",
        )

    def test_evidence_uses_the_identity_captured_for_the_run(self) -> None:
        captured_artifact = ("c" * 64, 42)
        captured_configuration = {
            "identifier": "captured-config",
            "preferredComputeUnit": "cpu",
            "expectsFrequentReshapes": False,
            "contextTokens": None,
            "staticInputShapes": {},
            "sha256Digest": "d" * 64,
        }

        evidence = harness.device_trial_evidence(
            run_mode="dryRun",
            device=harness.Device.from_document(device_document()),
            execution_succeeded=False,
            captured_at=datetime(2027, 1, 2, tzinfo=UTC),
            artifact_identity=captured_artifact,
            configuration_identity=captured_configuration,
        )

        self.assertEqual(evidence["artifact"]["sha256Digest"], "c" * 64)
        self.assertEqual(evidence["artifact"]["byteCount"], 42)
        self.assertEqual(evidence["configuration"], captured_configuration)

    def test_generated_dry_run_matches_the_cross_language_fixture(self) -> None:
        evidence = harness.device_trial_evidence(
            run_mode="dryRun",
            device=harness.Device.from_document(device_document()),
            execution_succeeded=False,
            captured_at=datetime(2027, 1, 2, 3, 4, 5, tzinfo=UTC),
        )
        fixture = (
            harness.REPOSITORY_ROOT
            / "CoreAILabTests"
            / "Fixtures"
            / "DeviceLabDryRunEvidence.json"
        )

        self.assertEqual(json.loads(fixture.read_text()), evidence)

    def test_evidence_writer_is_machine_readable_and_never_overwrites(self) -> None:
        evidence = harness.device_trial_evidence(
            run_mode="dryRun",
            device=harness.Device.from_document(device_document()),
            execution_succeeded=False,
            captured_at=datetime(2027, 1, 2, tzinfo=UTC),
        )
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "evidence.json"
            harness.write_evidence(evidence, output)

            self.assertEqual(json.loads(output.read_text()), evidence)
            with self.assertRaisesRegex(
                harness.DeviceTestHarnessError,
                "already exists",
            ):
                harness.write_evidence(evidence, output)


if __name__ == "__main__":
    unittest.main()
