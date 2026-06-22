import Foundation

struct CoreAIExportVerifierScriptGenerator: Sendable {
    func generate(
        targetName: String,
        generatedSourceFileName: String,
        resourceAccessorFileName: String,
        expectedPackageManifest: String
    ) -> String {
        let targetLiteral = pythonLiteral(targetName)
        let generatedSourceLiteral = pythonLiteral(generatedSourceFileName)
        let resourceAccessorLiteral = pythonLiteral(resourceAccessorFileName)
        let packageManifestLiteral = pythonLiteral(expectedPackageManifest)
        return """
            #!/usr/bin/env python3
            import argparse
            import hashlib
            import json
            import os
            from pathlib import Path, PurePosixPath
            import stat
            import subprocess
            import tempfile
            import unicodedata

            ROOT = Path(__file__).resolve().parent
            TARGET_NAME = \(targetLiteral)
            GENERATED_SOURCE_FILE_NAME = \(generatedSourceLiteral)
            RESOURCE_ACCESSOR_FILE_NAME = \(resourceAccessorLiteral)
            EXPECTED_PACKAGE_MANIFEST = \(packageManifestLiteral)
            TARGET_ROOT = ROOT / "Sources" / TARGET_NAME
            RESOURCE_ROOT = TARGET_ROOT / "Resources"
            MANIFEST_PATH = RESOURCE_ROOT / "coreai-export.json"
            CHECKSUMS_PATH = ROOT / "coreai-checksums.json"


            def fail(message):
                raise SystemExit(f"verification failed: {message}")


            def normalized(value):
                return unicodedata.normalize("NFC", value)


            def utf8_key(value):
                return value.encode("utf-8")


            def load_json(path):
                try:
                    with path.open("r", encoding="utf-8") as handle:
                        return json.load(handle)
                except (OSError, ValueError) as error:
                    fail(f"cannot read {path.relative_to(ROOT)}: {error}")


            def checked_relative(root, value):
                if not isinstance(value, str):
                    fail("manifest path is not a string")
                if normalized(value) != value:
                    fail(f"path is not NFC-normalized: {value!r}")
                relative = PurePosixPath(value)
                if relative.is_absolute() or value != relative.as_posix():
                    fail(f"non-canonical relative path: {value!r}")
                if not relative.parts or any(part in ("", ".", "..") for part in relative.parts):
                    fail(f"unsafe relative path: {value!r}")
                candidate = root
                for part in relative.parts:
                    candidate = candidate / part
                    if candidate.is_symlink():
                        fail(f"symbolic link is not allowed: {candidate.relative_to(ROOT)}")
                return candidate


            def file_identity(file_status):
                return (
                    file_status.st_dev,
                    file_status.st_ino,
                    stat.S_IFMT(file_status.st_mode),
                    file_status.st_size,
                    file_status.st_mtime_ns,
                    file_status.st_ctime_ns,
                )


            def digest_file(path):
                flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
                try:
                    before_path = os.lstat(path)
                    descriptor = os.open(path, flags)
                except OSError as error:
                    fail(f"cannot open {path.relative_to(ROOT)}: {error}")
                digest = hashlib.sha256()
                byte_count = 0
                try:
                    before_descriptor = os.fstat(descriptor)
                    if file_identity(before_descriptor) != file_identity(before_path):
                        fail(f"file changed before hashing: {path.relative_to(ROOT)}")
                    while chunk := os.read(descriptor, 1024 * 1024):
                        digest.update(chunk)
                        byte_count += len(chunk)
                    after_descriptor = os.fstat(descriptor)
                    after_path = os.lstat(path)
                    if (
                        file_identity(after_descriptor) != file_identity(before_descriptor)
                        or file_identity(after_path) != file_identity(before_descriptor)
                        or byte_count != before_descriptor.st_size
                    ):
                        fail(f"file changed while hashing: {path.relative_to(ROOT)}")
                except OSError as error:
                    fail(f"cannot hash {path.relative_to(ROOT)}: {error}")
                finally:
                    os.close(descriptor)
                return digest.hexdigest(), byte_count


            def package_entries():
                files = []
                directories = []
                logical_paths = set()
                for directory, directory_names, file_names in os.walk(ROOT, followlinks=False):
                    directory_path = Path(directory)
                    directory_names.sort(key=utf8_key)
                    file_names.sort(key=utf8_key)
                    for name in directory_names:
                        child = directory_path / name
                        relative = child.relative_to(ROOT).as_posix()
                        if child.is_symlink():
                            fail(f"symbolic link is not allowed: {relative}")
                        logical = normalized(relative)
                        if logical in logical_paths:
                            fail(f"paths collide after NFC normalization: {logical!r}")
                        logical_paths.add(logical)
                        directories.append(logical)
                    for name in file_names:
                        child = directory_path / name
                        relative = child.relative_to(ROOT).as_posix()
                        if child.is_symlink():
                            fail(f"symbolic link is not allowed: {relative}")
                        if not child.is_file():
                            fail(f"unsupported package item: {relative}")
                        logical = normalized(relative)
                        if logical in logical_paths:
                            fail(f"paths collide after NFC normalization: {logical!r}")
                        logical_paths.add(logical)
                        files.append(logical)
                return (
                    sorted(files, key=utf8_key),
                    sorted(directories, key=utf8_key),
                )


            def verify_layout(manifest, files, directories):
                artifact = manifest.get("artifact")
                if not isinstance(artifact, dict):
                    fail("artifact metadata is missing")
                artifact_relative_path = artifact.get("relativePath")
                artifact_path = checked_relative(ROOT, artifact_relative_path)
                try:
                    artifact_path.relative_to(RESOURCE_ROOT)
                except ValueError:
                    fail("artifact is outside the generated resource bundle")

                allowed_files = {
                    "Package.swift",
                    "README.md",
                    "compile-model.sh",
                    "coreai-checksums.json",
                    "verify-export.py",
                    f"Sources/{TARGET_NAME}/{GENERATED_SOURCE_FILE_NAME}",
                    f"Sources/{TARGET_NAME}/{RESOURCE_ACCESSOR_FILE_NAME}",
                    f"Sources/{TARGET_NAME}/Resources/THIRD_PARTY_NOTICES.md",
                    f"Sources/{TARGET_NAME}/Resources/coreai-export.json",
                }
                artifact_prefix = artifact_relative_path + "/"
                missing_files = allowed_files.difference(files)
                if missing_files:
                    fail(
                        "required package files are missing: "
                        + ", ".join(sorted(missing_files, key=utf8_key))
                    )
                for path in files:
                    if path not in allowed_files and not path.startswith(artifact_prefix):
                        fail(f"unexpected package file: {path}")

                allowed_directories = {
                    "Sources",
                    f"Sources/{TARGET_NAME}",
                    f"Sources/{TARGET_NAME}/Resources",
                    artifact_relative_path,
                }
                missing_directories = allowed_directories.difference(directories)
                if missing_directories:
                    fail(
                        "required package directories are missing: "
                        + ", ".join(sorted(missing_directories, key=utf8_key))
                    )
                for path in directories:
                    if path not in allowed_directories and not path.startswith(artifact_prefix):
                        fail(f"unexpected package directory: {path}")
                if "Package.resolved" in files:
                    fail("Package.resolved is not allowed in a clean export")


            def verify_package_policy():
                try:
                    package_source = (ROOT / "Package.swift").read_bytes()
                except OSError as error:
                    fail(f"cannot read Package.swift: {error}")
                expected_source = EXPECTED_PACKAGE_MANIFEST.encode("utf-8")
                if package_source != expected_source:
                    fail("Package.swift does not exactly match the generated dependency-free template")


            def verify_checksums(files):
                document = load_json(CHECKSUMS_PATH)
                if document.get("schemaVersion") != 1:
                    fail("unsupported checksum schema")
                records = document.get("files")
                if not isinstance(records, list):
                    fail("checksum file list is missing")
                paths = []
                for record in records:
                    if not isinstance(record, dict) or not isinstance(record.get("relativePath"), str):
                        fail("checksum record is malformed")
                    path = record["relativePath"]
                    checked_relative(ROOT, path)
                    paths.append(path)
                if (
                    paths != sorted(paths, key=utf8_key)
                    or len(paths) != len(set(paths))
                ):
                    fail("checksum paths must be unique and UTF-8 byte sorted")
                actual_paths = [path for path in files if path != "coreai-checksums.json"]
                if paths != actual_paths:
                    fail("whole-package inventory does not match coreai-checksums.json")
                hexadecimal = set("0123456789abcdef")
                for record in records:
                    path = checked_relative(ROOT, record["relativePath"])
                    expected_digest = record.get("sha256")
                    expected_count = record.get("byteCount")
                    if (
                        not isinstance(expected_digest, str)
                        or len(expected_digest) != 64
                        or any(character not in hexadecimal for character in expected_digest)
                    ):
                        fail(f"invalid SHA-256 for {record['relativePath']}")
                    if not isinstance(expected_count, int) or expected_count < 0:
                        fail(f"invalid byte count for {record['relativePath']}")
                    digest, byte_count = digest_file(path)
                    if digest != expected_digest or byte_count != expected_count:
                        fail(f"checksum mismatch: {record['relativePath']}")


            def verify_artifact(manifest):
                artifact = manifest["artifact"]
                artifact_path = checked_relative(ROOT, artifact["relativePath"])
                if not artifact_path.is_dir() or artifact_path.is_symlink():
                    fail("artifact directory is unavailable")

                digest = hashlib.sha256()
                total_byte_count = 0
                entries = list(artifact_path.rglob("*"))
                logical_paths = set()
                for entry in entries:
                    relative = entry.relative_to(artifact_path).as_posix()
                    logical = normalized(relative)
                    if logical in logical_paths:
                        fail(f"artifact paths collide after NFC normalization: {logical!r}")
                    logical_paths.add(logical)
                entries.sort(
                    key=lambda path: utf8_key(
                        normalized(path.relative_to(artifact_path).as_posix())
                    )
                )
                for entry in entries:
                    relative = normalized(entry.relative_to(artifact_path).as_posix())
                    if entry.is_symlink():
                        fail(f"symbolic link is not allowed: {entry.relative_to(ROOT)}")
                    if entry.is_dir():
                        digest.update(f"D\\0{relative}\\0".encode("utf-8"))
                    elif entry.is_file():
                        file_digest, byte_count = digest_file(entry)
                        digest.update(f"F\\0{relative}\\0{byte_count}\\0".encode("utf-8"))
                        digest.update(bytes.fromhex(file_digest))
                        total_byte_count += byte_count
                    else:
                        fail(f"unsupported artifact item: {entry.relative_to(ROOT)}")
                if digest.hexdigest() != artifact.get("sha256"):
                    fail("artifact tree digest does not match coreai-export.json")
                if total_byte_count != artifact.get("byteCount"):
                    fail("artifact byte count does not match coreai-export.json")


            def verify_structure():
                manifest = load_json(MANIFEST_PATH)
                if manifest.get("schemaVersion") != 2:
                    fail("unsupported export manifest schema")
                package = manifest.get("package")
                if not isinstance(package, dict):
                    fail("package metadata is missing")
                if package.get("targetName") != TARGET_NAME:
                    fail("package target metadata does not match the generated package")
                if package.get("name") != TARGET_NAME or package.get("productName") != TARGET_NAME:
                    fail("package identity metadata does not match the generated package")
                if package.get("swiftToolsVersion") != "6.4":
                    fail("package tools-version metadata is unsupported")
                resource_relative_path = RESOURCE_ROOT.relative_to(ROOT).as_posix()
                if package.get("resourcesRelativePath") != resource_relative_path:
                    fail("package resource metadata does not match the generated package")
                expected_source_path = f"Sources/{TARGET_NAME}/{GENERATED_SOURCE_FILE_NAME}"
                if package.get("generatedSourceRelativePath") != expected_source_path:
                    fail("generated source metadata does not match the generated package")
                if not isinstance(manifest.get("metadata"), dict):
                    fail("asset metadata is missing")
                if not isinstance(manifest.get("functions"), list):
                    fail("function contract metadata is missing")

                files, directories = package_entries()
                verify_layout(manifest, files, directories)
                verify_checksums(files)
                verify_package_policy()
                verify_artifact(manifest)


            def build_package():
                environment = os.environ.copy()
                environment["SWIFTPM_DISABLE_PACKAGE_REPOSITORY_CACHE"] = "1"
                with tempfile.TemporaryDirectory(prefix="coreai-export-verification-") as scratch:
                    command = [
                        "/usr/bin/xcrun",
                        "swift",
                        "build",
                        "--package-path",
                        str(ROOT),
                        "--scratch-path",
                        scratch,
                        "--disable-automatic-resolution",
                    ]
                    try:
                        subprocess.run(command, check=True, env=environment)
                    except (OSError, subprocess.CalledProcessError) as error:
                        fail(f"generated Swift package did not build: {error}")


            def main():
                parser = argparse.ArgumentParser(
                    description="Verify this Core AI integration without running coreai-build."
                )
                parser.add_argument(
                    "--structure-only",
                    action="store_true",
                    help="verify package structure and checksums without compiling Swift source",
                )
                arguments = parser.parse_args()
                verify_structure()
                if not arguments.structure_only:
                    build_package()
                print("Core AI integration export verified.")


            if __name__ == "__main__":
                main()
            """ + "\n"
    }

    private func pythonLiteral(_ value: String) -> String {
        var output = "\""
        let hexadecimal = Array("0123456789abcdef".utf8)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: output += "\\\""
            case 0x5C: output += "\\\\"
            case 0x0A: output += "\\n"
            case 0x0D: output += "\\r"
            case 0x09: output += "\\t"
            case 0x00...0x1F, 0x7F:
                let value = Int(scalar.value)
                let digits = [hexadecimal[(value >> 4) & 0xF], hexadecimal[value & 0xF]]
                output += "\\x" + String(decoding: digits, as: UTF8.self)
            default: output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }
}
