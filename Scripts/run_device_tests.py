#!/usr/bin/env python3
"""Run the real Core AI fixture test on one eligible physical iOS device."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import plistlib
import re
import shlex
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Mapping, Sequence


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
APP_BUNDLE_IDENTIFIERS = (
    "com.rudrank.CoreAILab",
    "com.rudrank.CoreAILabTests",
)
REAL_FIXTURE_TEST = (
    "CoreAILabTests/CoreAIFunctionWorkbenchTests/"
    "realCoreAIFixtureRunsFloatAndIntegerFunctions()"
)
TEAM_IDENTIFIER_PATTERN = re.compile(r"^[A-Z0-9]{10}$")
IDENTITY_HASH_PATTERN = re.compile(r"\b[0-9A-Fa-f]{40}\b")


class DeviceTestHarnessError(RuntimeError):
    """A validation or local-tooling failure that makes a run unsafe."""


@dataclass(frozen=True)
class Device:
    name: str
    identifier: str
    destination_identifier: str
    platform: str
    reality: str
    os_version: str
    boot_state: str
    tunnel_state: str
    pairing_state: str
    developer_mode_status: str
    ddi_services_available: bool

    @classmethod
    def from_document(cls, document: Mapping[str, Any]) -> Device:
        connection = _mapping(document.get("connectionProperties"))
        device = _mapping(document.get("deviceProperties"))
        hardware = _mapping(document.get("hardwareProperties"))
        properties = _mapping(document.get("properties"))
        property_hardware = _mapping(properties.get("hardware"))
        property_software = _mapping(properties.get("software"))
        property_state = _mapping(properties.get("state"))

        destination_identifier = _first_string(
            hardware.get("udid"),
            property_hardware.get("udid"),
        )
        os_version = _version_string(
            device.get("osVersionNumber"),
            property_software.get("osVersionNumber"),
        )
        developer_mode = _first_string(
            device.get("developerModeStatus"),
            _developer_mode_string(property_state.get("developerModeStatus")),
        )
        return cls(
            name=_first_string(device.get("name"), property_state.get("name")),
            identifier=_first_string(document.get("identifier")),
            destination_identifier=destination_identifier,
            platform=_first_string(hardware.get("platform")),
            reality=_first_string(
                hardware.get("reality"),
                property_hardware.get("reality"),
            ),
            os_version=os_version,
            boot_state=_first_string(
                device.get("bootState"),
                property_state.get("bootState"),
            ),
            tunnel_state=_first_string(connection.get("tunnelState")),
            pairing_state=_first_string(connection.get("pairingState")),
            developer_mode_status=developer_mode,
            ddi_services_available=device.get("ddiServicesAvailable") is True,
        )

    def rejection_reasons(self) -> list[str]:
        reasons: list[str] = []
        if self.platform.casefold() != "ios":
            reasons.append(f"platform is {self.platform or 'unknown'}, not iOS")
        if self.reality.casefold() != "physical":
            reasons.append(f"reality is {self.reality or 'unknown'}, not physical")
        if self.boot_state.casefold() != "booted":
            reasons.append(f"boot state is {self.boot_state or 'unknown'}")
        if self.tunnel_state.casefold() != "connected":
            reasons.append(f"device tunnel is {self.tunnel_state or 'unknown'}")
        if self.pairing_state.casefold() != "paired":
            reasons.append(f"pairing state is {self.pairing_state or 'unknown'}")
        if self.developer_mode_status.casefold() != "enabled":
            reasons.append(
                "Developer Mode is "
                f"{self.developer_mode_status or 'unknown'}"
            )
        if not self.ddi_services_available:
            reasons.append("developer disk image services are unavailable")
        if _major_version(self.os_version) < 27:
            reasons.append(f"iOS {self.os_version or 'unknown'} is older than 27")
        if not self.destination_identifier:
            reasons.append("the physical UDID needed by xcodebuild is missing")
        return reasons

    def matches(self, selector: str) -> bool:
        normalized = selector.casefold()
        return normalized in {
            self.name.casefold(),
            self.identifier.casefold(),
            self.destination_identifier.casefold(),
        }


@dataclass(frozen=True)
class SigningProfile:
    path: Path
    name: str
    uuid: str
    team_identifiers: tuple[str, ...]
    platforms: tuple[str, ...]
    application_identifier: str
    expiration_date: datetime
    provisioned_devices: frozenset[str]
    permits_debugging: bool
    certificate_hashes: frozenset[str]

    @classmethod
    def from_plist(cls, path: Path, document: Mapping[str, Any]) -> SigningProfile:
        entitlements = _mapping(document.get("Entitlements"))
        expiration = document.get("ExpirationDate")
        if not isinstance(expiration, datetime):
            raise DeviceTestHarnessError(
                f"Provisioning profile has no expiration date: {path}"
            )
        if expiration.tzinfo is None:
            expiration = expiration.replace(tzinfo=UTC)

        certificates = document.get("DeveloperCertificates", [])
        certificate_hashes = frozenset(
            hashlib.sha1(certificate).hexdigest().upper()
            for certificate in certificates
            if isinstance(certificate, bytes)
        )
        return cls(
            path=path,
            name=_first_string(document.get("Name")),
            uuid=_first_string(document.get("UUID")),
            team_identifiers=tuple(_string_list(document.get("TeamIdentifier"))),
            platforms=tuple(_string_list(document.get("Platform"))),
            application_identifier=_first_string(
                entitlements.get("application-identifier")
            ),
            expiration_date=expiration,
            provisioned_devices=frozenset(
                _string_list(document.get("ProvisionedDevices"))
            ),
            permits_debugging=entitlements.get("get-task-allow") is True,
            certificate_hashes=certificate_hashes,
        )

    def matches(self, selector: str) -> bool:
        normalized = selector.casefold()
        return normalized in {
            self.name.casefold(),
            self.uuid.casefold(),
            self.path.name.casefold(),
            str(self.path).casefold(),
        }

    def rejection_reasons(
        self,
        *,
        team_identifier: str,
        device_identifier: str,
        installed_identity_hashes: frozenset[str],
        now: datetime,
    ) -> list[str]:
        reasons: list[str] = []
        if team_identifier not in self.team_identifiers:
            reasons.append("belongs to another development team")
        if not any(platform.casefold() == "ios" for platform in self.platforms):
            reasons.append("is not an iOS provisioning profile")
        if self.expiration_date <= now:
            reasons.append("is expired")
        if device_identifier not in self.provisioned_devices:
            reasons.append("does not include the selected device")
        if not self.permits_debugging:
            reasons.append("does not permit development debugging")
        if not self.certificate_hashes.intersection(installed_identity_hashes):
            reasons.append("has no matching local code-signing private key")
        for bundle_identifier in APP_BUNDLE_IDENTIFIERS:
            if not _application_identifier_matches(
                self.application_identifier,
                team_identifier,
                bundle_identifier,
            ):
                reasons.append(f"does not cover {bundle_identifier}")
        return reasons


def _mapping(value: object) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _first_string(*values: object) -> str:
    for value in values:
        if isinstance(value, str) and value:
            return value
    return ""


def _string_list(value: object) -> list[str]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)):
        return []
    return [item for item in value if isinstance(item, str)]


def _developer_mode_string(value: object) -> str:
    mapping = _mapping(value)
    if "enabled" in mapping:
        return "enabled"
    if "disabled" in mapping:
        return "disabled"
    return ""


def _version_string(*values: object) -> str:
    for value in values:
        if isinstance(value, str) and value:
            return value
        mapping = _mapping(value)
        string_value = mapping.get("stringValue")
        if isinstance(string_value, str) and string_value:
            return string_value
        components = mapping.get("components")
        if isinstance(components, list) and components:
            numeric = [str(item) for item in components if isinstance(item, int)]
            if numeric:
                return ".".join(numeric)
    return ""


def _major_version(version: str) -> int:
    try:
        return int(version.split(".", maxsplit=1)[0])
    except (TypeError, ValueError):
        return -1


def _application_identifier_matches(
    application_identifier: str,
    team_identifier: str,
    bundle_identifier: str,
) -> bool:
    prefix = f"{team_identifier}."
    if not application_identifier.startswith(prefix):
        return False
    pattern = application_identifier.removeprefix(prefix)
    return fnmatch.fnmatchcase(bundle_identifier, pattern)


def devicectl_command(json_output: Path) -> list[str]:
    return [
        "xcrun",
        "devicectl",
        "list",
        "devices",
        "--quiet",
        "--json-output",
        str(json_output),
    ]


def load_device_document() -> Mapping[str, Any]:
    with tempfile.TemporaryDirectory(prefix="coreai-device-discovery-") as directory:
        output = Path(directory) / "devices.json"
        completed = subprocess.run(
            devicectl_command(output),
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode != 0:
            detail = completed.stderr.strip() or completed.stdout.strip()
            raise DeviceTestHarnessError(f"devicectl failed: {detail}")
        try:
            return _mapping(json.loads(output.read_text()))
        except (FileNotFoundError, json.JSONDecodeError) as error:
            raise DeviceTestHarnessError(
                f"devicectl did not produce valid JSON: {error}"
            ) from error


def devices_from_document(document: Mapping[str, Any]) -> list[Device]:
    info = _mapping(document.get("info"))
    if info.get("outcome") not in (None, "success"):
        raise DeviceTestHarnessError(
            f"devicectl reported outcome {info.get('outcome')!r}"
        )
    result = _mapping(document.get("result"))
    raw_devices = result.get("devices")
    if not isinstance(raw_devices, list):
        raise DeviceTestHarnessError("devicectl JSON has no result.devices array")
    return [Device.from_document(item) for item in raw_devices if isinstance(item, Mapping)]


def select_device(devices: Sequence[Device], selector: str | None) -> Device:
    if selector:
        matches = [device for device in devices if device.matches(selector)]
        if not matches:
            raise DeviceTestHarnessError(f"No device exactly matches {selector!r}")
        if len(matches) > 1:
            raise DeviceTestHarnessError(
                f"Device selector {selector!r} is ambiguous; use a physical UDID"
            )
        device = matches[0]
        reasons = device.rejection_reasons()
        if reasons:
            raise DeviceTestHarnessError(
                f"Device {device.name or selector!r} is ineligible: "
                + "; ".join(reasons)
            )
        return device

    eligible = [device for device in devices if not device.rejection_reasons()]
    if not eligible:
        raise DeviceTestHarnessError(
            "No connected physical iOS 27+ device is ready for development testing"
        )
    if len(eligible) > 1:
        choices = ", ".join(
            f"{device.name} ({device.destination_identifier})" for device in eligible
        )
        raise DeviceTestHarnessError(
            f"Multiple eligible physical devices found: {choices}. Pass --device."
        )
    return eligible[0]


def installed_identity_hashes() -> frozenset[str]:
    completed = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise DeviceTestHarnessError(
            "Unable to inspect local code-signing identities: "
            + (completed.stderr.strip() or completed.stdout.strip())
        )
    return frozenset(
        match.group(0).upper()
        for match in IDENTITY_HASH_PATTERN.finditer(completed.stdout)
    )


def installed_profile_paths(home: Path | None = None) -> list[Path]:
    root = home or Path.home()
    directories = (
        root / "Library/Developer/Xcode/UserData/Provisioning Profiles",
        root / "Library/MobileDevice/Provisioning Profiles",
    )
    paths: set[Path] = set()
    for directory in directories:
        for pattern in ("*.mobileprovision", "*.provisionprofile"):
            paths.update(directory.glob(pattern))
    return sorted(paths)


def load_signing_profiles(paths: Sequence[Path]) -> list[SigningProfile]:
    profiles: list[SigningProfile] = []
    seen_uuids: set[str] = set()
    for path in paths:
        completed = subprocess.run(
            ["security", "cms", "-D", "-i", str(path)],
            capture_output=True,
            check=False,
        )
        if completed.returncode != 0:
            continue
        try:
            document = plistlib.loads(completed.stdout)
            profile = SigningProfile.from_plist(path, _mapping(document))
        except (plistlib.InvalidFileException, DeviceTestHarnessError):
            continue
        if profile.uuid and profile.uuid not in seen_uuids:
            profiles.append(profile)
            seen_uuids.add(profile.uuid)
    return profiles


def select_signing_profile(
    profiles: Sequence[SigningProfile],
    *,
    selector: str | None,
    team_identifier: str,
    device_identifier: str,
    identity_hashes: frozenset[str],
    now: datetime | None = None,
) -> SigningProfile:
    candidates = list(profiles)
    if selector:
        candidates = [profile for profile in candidates if profile.matches(selector)]
        if not candidates:
            raise DeviceTestHarnessError(
                f"No installed provisioning profile exactly matches {selector!r}"
            )

    current_time = now or datetime.now(UTC)
    eligible: list[SigningProfile] = []
    rejected: list[str] = []
    for profile in candidates:
        reasons = profile.rejection_reasons(
            team_identifier=team_identifier,
            device_identifier=device_identifier,
            installed_identity_hashes=identity_hashes,
            now=current_time,
        )
        if reasons:
            rejected.append(f"{profile.name} ({profile.uuid}): " + "; ".join(reasons))
        else:
            eligible.append(profile)

    if not eligible:
        detail = "\n  ".join(rejected[:8])
        suffix = f"\n  {detail}" if detail else ""
        raise DeviceTestHarnessError(
            "No installed development profile covers the app, test bundle, "
            f"team, device, and a local private key.{suffix}"
        )
    if len(eligible) > 1:
        choices = ", ".join(f"{item.name} ({item.uuid})" for item in eligible)
        raise DeviceTestHarnessError(
            f"Multiple eligible provisioning profiles found: {choices}. Pass --profile."
        )
    return eligible[0]


def xcodebuild_command(
    *,
    device: Device,
    team_identifier: str,
    result_bundle: Path,
    derived_data: Path,
) -> list[str]:
    return [
        "xcodebuild",
        "test",
        "-project",
        "CoreAIFrameworkLab.xcodeproj",
        "-scheme",
        "CoreAILab",
        "-configuration",
        "Debug",
        "-destination",
        f"platform=iOS,id={device.destination_identifier}",
        "-destination-timeout",
        "30",
        "-only-testing:" + REAL_FIXTURE_TEST,
        "-disableAutomaticPackageResolution",
        "-skipPackageUpdates",
        "-parallel-testing-enabled",
        "NO",
        "-derivedDataPath",
        str(derived_data),
        "-resultBundlePath",
        str(result_bundle),
        "CODE_SIGNING_ALLOWED=YES",
        "CODE_SIGNING_REQUIRED=YES",
        "CODE_SIGN_STYLE=Automatic",
        f"DEVELOPMENT_TEAM={team_identifier}",
        "CODE_SIGN_IDENTITY=Apple Development",
    ]


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


def validate_xcresult_summary(
    document: Mapping[str, Any],
    *,
    expected_device_identifier: str,
) -> None:
    expected_counts = {
        "totalTestCount": 1,
        "passedTests": 1,
        "failedTests": 0,
        "skippedTests": 0,
        "expectedFailures": 0,
    }
    actual_counts = {key: document.get(key) for key in expected_counts}
    if document.get("result") != "Passed" or actual_counts != expected_counts:
        raise DeviceTestHarnessError(
            "xcresult did not prove exactly one passed fixture test: "
            f"result={document.get('result')!r}, counts={actual_counts}"
        )

    configurations = document.get("devicesAndConfigurations")
    if not isinstance(configurations, list) or len(configurations) != 1:
        raise DeviceTestHarnessError(
            "xcresult did not report exactly one device configuration"
        )
    configuration = _mapping(configurations[0])
    device = _mapping(configuration.get("device"))
    configuration_counts = {
        key: configuration.get(key)
        for key in ("passedTests", "failedTests", "skippedTests", "expectedFailures")
    }
    if (
        device.get("platform") != "iOS"
        or device.get("deviceId") != expected_device_identifier
        or configuration_counts
        != {
            "passedTests": 1,
            "failedTests": 0,
            "skippedTests": 0,
            "expectedFailures": 0,
        }
    ):
        raise DeviceTestHarnessError(
            "xcresult did not attribute one passing test to the selected physical "
            f"iOS device {expected_device_identifier}: device={dict(device)}, "
            f"counts={configuration_counts}"
        )


def validate_team_identifier(value: str) -> str:
    normalized = value.upper()
    if not TEAM_IDENTIFIER_PATTERN.fullmatch(normalized):
        raise argparse.ArgumentTypeError(
            "team must be the 10-character Apple Developer Team ID"
        )
    return normalized


def parse_arguments(arguments: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run the bundled real Core AI fixture test on exactly one connected "
            "physical iOS 27+ device using only installed signing assets."
        )
    )
    parser.add_argument(
        "--team",
        required=True,
        type=validate_team_identifier,
        help="Apple Developer Team ID used by an installed development profile.",
    )
    parser.add_argument(
        "--device",
        help="Exact device name, CoreDevice identifier, or physical UDID.",
    )
    parser.add_argument(
        "--profile",
        help="Exact installed provisioning profile name, UUID, or file name.",
    )
    parser.add_argument(
        "--result-bundle",
        type=Path,
        help="New .xcresult path (defaults to a timestamp below TestResults).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate discovery/signing and print the command without running it.",
    )
    return parser.parse_args(arguments)


def default_result_bundle() -> Path:
    timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    return REPOSITORY_ROOT / "TestResults" / f"CoreAIDeviceTests-{timestamp}.xcresult"


def main(arguments: Sequence[str] | None = None) -> int:
    options = parse_arguments(arguments)
    try:
        device = select_device(
            devices_from_document(load_device_document()),
            options.device,
        )
        identities = installed_identity_hashes()
        profile = select_signing_profile(
            load_signing_profiles(installed_profile_paths()),
            selector=options.profile,
            team_identifier=options.team,
            device_identifier=device.destination_identifier,
            identity_hashes=identities,
        )

        result_bundle = options.result_bundle or default_result_bundle()
        if not result_bundle.is_absolute():
            result_bundle = REPOSITORY_ROOT / result_bundle
        result_bundle = result_bundle.resolve()
        if result_bundle.suffix != ".xcresult":
            raise DeviceTestHarnessError("--result-bundle must end in .xcresult")
        if result_bundle.exists():
            raise DeviceTestHarnessError(
                f"Result bundle already exists; choose a new path: {result_bundle}"
            )

        command = xcodebuild_command(
            device=device,
            team_identifier=options.team,
            result_bundle=result_bundle,
            derived_data=REPOSITORY_ROOT / "build/DeviceTests",
        )
        print(
            f"Device: {device.name} ({device.destination_identifier}), "
            f"iOS {device.os_version}"
        )
        print(f"Validated local profile: {profile.name} ({profile.uuid})")
        print(shlex.join(command))
        if options.dry_run:
            return 0

        result_bundle.parent.mkdir(parents=True, exist_ok=True)
        completed = subprocess.run(command, cwd=REPOSITORY_ROOT, check=False)
        if not result_bundle.exists():
            if completed.returncode != 0:
                return completed.returncode
            raise DeviceTestHarnessError(
                "xcodebuild succeeded without an xcresult bundle"
            )

        summary = subprocess.run(
            xcresult_summary_command(result_bundle),
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        if summary.returncode != 0:
            detail = summary.stderr.strip() or summary.stdout.strip()
            if completed.returncode != 0:
                print(
                    "xcresulttool could not summarize the failed run: " + detail,
                    file=sys.stderr,
                )
                return completed.returncode
            raise DeviceTestHarnessError(
                "xcodebuild succeeded but xcresulttool could not summarize its result: "
                + detail
            )
        try:
            document = json.loads(summary.stdout)
        except json.JSONDecodeError as error:
            if completed.returncode != 0:
                print(summary.stdout.rstrip())
                return completed.returncode
            raise DeviceTestHarnessError(
                "xcodebuild succeeded but xcresulttool returned invalid JSON"
            ) from error

        print(json.dumps(document, indent=2, sort_keys=True))
        if completed.returncode != 0:
            return completed.returncode
        validate_xcresult_summary(
            _mapping(document),
            expected_device_identifier=device.destination_identifier,
        )
        return 0
    except DeviceTestHarnessError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
