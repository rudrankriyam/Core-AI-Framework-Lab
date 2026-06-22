import CryptoKit
import Darwin
import Foundation

protocol CoreAIConversionCheckpointArtifactVerifying: Sendable {
    func evidence(
        for expected: CoreAIConversionCheckpointArtifact,
        under rootURL: URL
    ) throws -> CoreAIConversionCheckpointArtifact
}

struct CoreAIConversionCheckpointArtifactVerifier: CoreAIConversionCheckpointArtifactVerifying {
    func evidence(
        for expected: CoreAIConversionCheckpointArtifact,
        under rootURL: URL
    ) throws -> CoreAIConversionCheckpointArtifact {
        try Task.checkCancellation()
        let rootDescriptor = open(
            rootURL.standardizedFileURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard rootDescriptor >= 0 else {
            throw CoreAIConversionJobStoreError.artifactVerificationFailed(
                expected.relativePath
            )
        }
        defer { close(rootDescriptor) }
        let descriptor = try openRelative(
            expected.relativePath,
            rootDescriptor: rootDescriptor,
            requiresDirectory: expected.digestScheme == .sha256TreeV1
        )
        defer { close(descriptor) }

        switch expected.digestScheme {
        case .sha256FileV1:
            let digest = try hashFile(descriptor: descriptor, path: expected.relativePath)
            return try CoreAIConversionCheckpointArtifact(
                kind: expected.kind,
                digestScheme: .sha256FileV1,
                relativePath: expected.relativePath,
                sha256: digest.sha256,
                byteCount: digest.byteCount,
                fileCount: 1
            )
        case .sha256TreeV1:
            var hasher = SHA256()
            var byteCount: Int64 = 0
            var fileCount = 0
            try hashTree(
                descriptor: descriptor,
                relativePrefix: "",
                hasher: &hasher,
                byteCount: &byteCount,
                fileCount: &fileCount
            )
            return try CoreAIConversionCheckpointArtifact(
                kind: expected.kind,
                digestScheme: .sha256TreeV1,
                relativePath: expected.relativePath,
                sha256: Data(hasher.finalize()).hexadecimalString,
                byteCount: byteCount,
                fileCount: fileCount
            )
        }
    }

    private func openRelative(
        _ relativePath: String,
        rootDescriptor: Int32,
        requiresDirectory: Bool
    ) throws -> Int32 {
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            throw CoreAIConversionJobStoreError.artifactVerificationFailed(relativePath)
        }
        var current = dup(rootDescriptor)
        guard current >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        for (index, component) in components.enumerated() {
            let isLast = index == components.count - 1
            var flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW
            if !isLast || requiresDirectory { flags |= O_DIRECTORY }
            let next = openat(current, component, flags)
            close(current)
            guard next >= 0 else {
                throw CoreAIConversionJobStoreError.artifactVerificationFailed(relativePath)
            }
            current = next
        }
        return current
    }

    private func hashTree(
        descriptor: Int32,
        relativePrefix: String,
        hasher: inout SHA256,
        byteCount: inout Int64,
        fileCount: inout Int
    ) throws {
        try Task.checkCancellation()
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFDIR else {
            throw CoreAIConversionJobStoreError.artifactVerificationFailed(relativePrefix)
        }
        let names = try directoryNames(descriptor: descriptor).sorted(by: utf8Precedes)
        for name in names {
            try Task.checkCancellation()
            let childPath = relativePrefix.isEmpty ? name : "\(relativePrefix)/\(name)"
            let child = openat(descriptor, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            guard child >= 0 else {
                throw CoreAIConversionJobStoreError.artifactVerificationFailed(childPath)
            }
            do {
                defer { close(child) }
                var status = stat()
                guard fstat(child, &status) == 0 else {
                    throw CoreAIConversionJobStoreError.artifactVerificationFailed(childPath)
                }
                switch status.st_mode & S_IFMT {
                case S_IFDIR:
                    update(&hasher, with: "D\0\(childPath)\0")
                    try hashTree(
                        descriptor: child,
                        relativePrefix: childPath,
                        hasher: &hasher,
                        byteCount: &byteCount,
                        fileCount: &fileCount
                    )
                case S_IFREG:
                    let digest = try hashFile(descriptor: child, path: childPath)
                    update(&hasher, with: "F\0\(childPath)\0\(digest.byteCount)\0")
                    hasher.update(data: digest.digestData)
                    byteCount += digest.byteCount
                    fileCount += 1
                default:
                    throw CoreAIConversionJobStoreError.artifactVerificationFailed(childPath)
                }
            }
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              stable(before, after) else {
            throw CoreAIConversionJobStoreError.artifactChangedDuringVerification(relativePrefix)
        }
    }

    private func hashFile(descriptor: Int32, path: String) throws -> FileDigest {
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw CoreAIConversionJobStoreError.artifactVerificationFailed(path)
        }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else {
                throw CoreAIConversionJobStoreError.artifactVerificationFailed(path)
            }
            if count == 0 { break }
            hasher.update(data: Data(buffer[0..<count]))
            byteCount += Int64(count)
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              stable(before, after),
              byteCount == before.st_size else {
            throw CoreAIConversionJobStoreError.artifactChangedDuringVerification(path)
        }
        let digestData = Data(hasher.finalize())
        return FileDigest(
            sha256: digestData.hexadecimalString,
            digestData: digestData,
            byteCount: byteCount
        )
    }

    private func directoryNames(descriptor: Int32) throws -> [String] {
        let duplicate = dup(descriptor)
        guard duplicate >= 0, let directory = fdopendir(duplicate) else {
            if duplicate >= 0 { close(duplicate) }
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        defer { closedir(directory) }
        var names: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return names
    }

    private func stable(_ first: stat, _ second: stat) -> Bool {
        first.st_dev == second.st_dev
            && first.st_ino == second.st_ino
            && first.st_mode == second.st_mode
            && first.st_size == second.st_size
            && first.st_mtimespec.tv_sec == second.st_mtimespec.tv_sec
            && first.st_mtimespec.tv_nsec == second.st_mtimespec.tv_nsec
            && first.st_ctimespec.tv_sec == second.st_ctimespec.tv_sec
            && first.st_ctimespec.tv_nsec == second.st_ctimespec.tv_nsec
    }

    private func utf8Precedes(_ first: String, _ second: String) -> Bool {
        Array(first.utf8).lexicographicallyPrecedes(Array(second.utf8))
    }

    private func update(_ hasher: inout SHA256, with value: String) {
        hasher.update(data: Data(value.utf8))
    }

    private struct FileDigest {
        let sha256: String
        let digestData: Data
        let byteCount: Int64
    }
}

private extension Data {
    var hexadecimalString: String {
        let digits = Array("0123456789abcdef".utf8)
        var output: [UInt8] = []
        output.reserveCapacity(count * 2)
        for byte in self {
            output.append(digits[Int(byte >> 4)])
            output.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: output, as: UTF8.self)
    }
}
