from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


SCRIPTS_DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_DIRECTORY))

import xcresult_public_summary as evidence  # noqa: E402


class PublicXCResultSummaryTests(unittest.TestCase):
    def test_summary_keeps_counts_and_removes_hardware_identifiers(self) -> None:
        raw = {
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
                        "deviceId": "SECRET-UDID",
                        "deviceName": "Personal iPhone",
                        "modelName": "Private Model",
                        "osVersion": "27.0-private-build",
                    }
                }
            ],
        }

        summary = evidence.public_summary(
            raw,
            evidence_kind="physical-ios-fixture",
            expected_platform="iOS",
        )

        encoded = json.dumps(summary)
        self.assertEqual(summary["result"], "Passed")
        self.assertEqual(summary["counts"]["passedTests"], 1)
        self.assertEqual(summary["platforms"], ["iOS"])
        self.assertTrue(summary["identifiersRedacted"])
        for private_value in (
            "SECRET-UDID",
            "Personal iPhone",
            "Private Model",
            "27.0-private-build",
        ):
            self.assertNotIn(private_value, encoded)

    def test_summary_rejects_an_unexpected_platform(self) -> None:
        raw = {
            "result": "Passed",
            "totalTestCount": 1,
            "passedTests": 1,
            "failedTests": 0,
            "skippedTests": 0,
            "expectedFailures": 0,
            "devicesAndConfigurations": [{"device": {"platform": "macOS"}}],
        }

        with self.assertRaisesRegex(
            evidence.PublicSummaryError,
            "expected iOS platform",
        ):
            evidence.public_summary(
                raw,
                evidence_kind="physical-ios-fixture",
                expected_platform="iOS",
            )

    def test_summary_rejects_missing_or_negative_counts(self) -> None:
        for value in (None, -1, True):
            with self.subTest(value=value):
                raw = {
                    "result": "Passed",
                    "totalTestCount": value,
                    "passedTests": 1,
                    "failedTests": 0,
                    "skippedTests": 0,
                    "expectedFailures": 0,
                    "devicesAndConfigurations": [
                        {"device": {"platform": "macOS"}}
                    ],
                }
                with self.assertRaises(evidence.PublicSummaryError):
                    evidence.public_summary(
                        raw,
                        evidence_kind="macos-contract-tests",
                        expected_platform="macOS",
                    )


if __name__ == "__main__":
    unittest.main()
