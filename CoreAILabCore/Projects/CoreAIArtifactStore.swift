import CryptoKit
import Foundation

actor CoreAIArtifactStore: CoreAIArtifactDigesting {
    nonisolated static let defaultRootURL = CoreAIStorageLocation.artifactRootURL
    nonisolated static let shared = CoreAIArtifactStore()

    nonisolated let rootURL: URL

    private let fileManager: FileManager
    private let readChunkSize = 1_048_576

    init(
        rootURL: URL = CoreAIArtifactStore.defaultRootURL,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func digest(at sourceURL: URL) async throws -> CoreAIArtifactDigest {
        try Task.checkCancellation()
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fingerprint = try fingerprint(at: sourceURL)
        return CoreAIArtifactDigest(
            sha256: fingerprint.sha256Digest,
            kind: fingerprint.kind,
            byteCount: fingerprint.byteCount,
            fileCount: fingerprint.fileCount
        )
    }

    func importArtifact(from sourceURL: URL) throws -> CoreAIStoredArtifact {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let sourceFingerprint = try fingerprint(at: sourceURL)
        let relativePath = storageRelativePath(for: sourceFingerprint)
        let destinationURL = url(for: relativePath)
        let destinationContainerURL = destinationURL.deletingLastPathComponent()

        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destinationContainerURL.path) {
            guard fileManager.fileExists(atPath: destinationURL.path) else {
                throw CoreAIArtifactStoreError.corruptedStoredArtifact(
                    sourceFingerprint.sha256Digest
                )
            }
            let storedFingerprint = try fingerprint(at: destinationURL)
            guard storedFingerprint.sha256Digest == sourceFingerprint.sha256Digest else {
                throw CoreAIArtifactStoreError.corruptedStoredArtifact(
                    sourceFingerprint.sha256Digest
                )
            }
            return sourceFingerprint.storedArtifact(
                relativePath: relativePath,
                originalFilename: sourceURL.lastPathComponent,
                wasAlreadyStored: true
            )
        }

        let stagingParentURL = rootURL
            .appending(path: ".staging", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stagedPayloadURL = stagingParentURL.appending(
            path: destinationURL.lastPathComponent,
            directoryHint: sourceFingerprint.isDirectory ? .isDirectory : .notDirectory
        )
        defer {
            try? fileManager.removeItem(at: stagingParentURL)
        }

        try fileManager.createDirectory(
            at: stagingParentURL,
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceURL, to: stagedPayloadURL)

        let stagedFingerprint = try fingerprint(at: stagedPayloadURL)
        guard stagedFingerprint == sourceFingerprint else {
            throw CoreAIArtifactStoreError.sourceChangedDuringImport
        }

        try fileManager.createDirectory(
            at: destinationContainerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try fileManager.moveItem(
                at: stagingParentURL,
                to: destinationContainerURL
            )
        } catch {
            guard fileManager.fileExists(atPath: destinationURL.path) else {
                throw error
            }
            let storedFingerprint = try fingerprint(at: destinationURL)
            guard storedFingerprint.sha256Digest == sourceFingerprint.sha256Digest else {
                throw CoreAIArtifactStoreError.corruptedStoredArtifact(
                    sourceFingerprint.sha256Digest
                )
            }
            return sourceFingerprint.storedArtifact(
                relativePath: relativePath,
                originalFilename: sourceURL.lastPathComponent,
                wasAlreadyStored: true
            )
        }

        return sourceFingerprint.storedArtifact(
            relativePath: relativePath,
            originalFilename: sourceURL.lastPathComponent,
            wasAlreadyStored: false
        )
    }

    func removeArtifact(at relativePath: String) throws {
        let artifactURL = try validatedURL(for: relativePath)
        let containerURL = artifactURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: containerURL.path) else { return }
        try fileManager.removeItem(at: containerURL)
    }

    nonisolated func url(for relativePath: String) -> URL {
        relativePath.split(separator: "/").reduce(rootURL) { partialURL, component in
            partialURL.appending(path: String(component))
        }
    }

    private func fingerprint(at sourceURL: URL) throws -> Fingerprint {
        try Task.checkCancellation()
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CoreAIArtifactStoreError.sourceMissing(sourceURL.lastPathComponent)
        }

        let rootValues = try sourceURL.resourceValues(
            forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        if rootValues.isSymbolicLink == true {
            throw CoreAIArtifactStoreError.symbolicLink(sourceURL.lastPathComponent)
        }
        guard rootValues.isDirectory == true || rootValues.isRegularFile == true else {
            throw CoreAIArtifactStoreError.unsupportedItem(sourceURL.lastPathComponent)
        }

        let isDirectory = rootValues.isDirectory == true
        let kind = CoreAIArtifactKind.infer(from: sourceURL, isDirectory: isDirectory)
        let pathExtension = sourceURL.pathExtension.lowercased()
        var hasher = SHA256()
        update("CoreAIArtifactStore/v1", in: &hasher)
        update(kind.rawValue, in: &hasher)
        update(pathExtension, in: &hasher)

        var byteCount: Int64 = 0
        var fileCount = 0
        if isDirectory {
            let entries = try entries(in: sourceURL)
            for entry in entries {
                try Task.checkCancellation()
                update(entry.isDirectory ? "directory" : "file", in: &hasher)
                update(entry.relativePath, in: &hasher)
                if !entry.isDirectory {
                    byteCount = try addFile(
                        at: entry.url,
                        to: &hasher,
                        currentByteCount: byteCount
                    )
                    fileCount += 1
                }
            }
        } else {
            update("file", in: &hasher)
            byteCount = try addFile(
                at: sourceURL,
                to: &hasher,
                currentByteCount: byteCount
            )
            fileCount = 1
        }

        return Fingerprint(
            sha256Digest: hexadecimal(hasher.finalize()),
            kind: kind,
            pathExtension: pathExtension,
            byteCount: byteCount,
            fileCount: fileCount,
            isDirectory: isDirectory
        )
    }

    private func entries(in rootURL: URL) throws -> [Entry] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ]
        ) else {
            throw CoreAIArtifactStoreError.unsupportedItem(rootURL.lastPathComponent)
        }

        let rootPath = rootURL.standardizedFileURL.path
        var entries: [Entry] = []
        for case let childURL as URL in enumerator {
            let values = try childURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            let childPath = childURL.standardizedFileURL.path
            guard childPath.hasPrefix(rootPath + "/") else {
                throw CoreAIArtifactStoreError.unsupportedItem(childURL.lastPathComponent)
            }
            let relativePath = String(childPath.dropFirst(rootPath.count + 1))
                .precomposedStringWithCanonicalMapping
            if values.isSymbolicLink == true {
                throw CoreAIArtifactStoreError.symbolicLink(relativePath)
            }
            guard values.isDirectory == true || values.isRegularFile == true else {
                throw CoreAIArtifactStoreError.unsupportedItem(relativePath)
            }
            entries.append(
                Entry(
                    url: childURL,
                    relativePath: relativePath,
                    isDirectory: values.isDirectory == true
                )
            )
        }
        return entries.sorted { $0.relativePath < $1.relativePath }
    }

    private func addFile(
        at url: URL,
        to hasher: inout SHA256,
        currentByteCount: Int64
    ) throws -> Int64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let expectedByteCount = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        update(expectedByteCount, in: &hasher)
        var updatedByteCount = currentByteCount
        var fileByteCount: UInt64 = 0
        while let chunk = try handle.read(upToCount: readChunkSize), !chunk.isEmpty {
            try Task.checkCancellation()
            let (nextFileByteCount, fileOverflow) = fileByteCount.addingReportingOverflow(
                UInt64(chunk.count)
            )
            let (nextByteCount, overflow) = updatedByteCount.addingReportingOverflow(
                Int64(chunk.count)
            )
            guard !fileOverflow, !overflow else {
                throw CoreAIArtifactStoreError.unsupportedItem(url.lastPathComponent)
            }
            fileByteCount = nextFileByteCount
            updatedByteCount = nextByteCount
            hasher.update(data: chunk)
        }
        guard fileByteCount == expectedByteCount else {
            throw CoreAIArtifactStoreError.sourceChangedDuringImport
        }
        return updatedByteCount
    }

    private func update(_ value: String, in hasher: inout SHA256) {
        let data = Data(value.utf8)
        var length = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &length) { hasher.update(bufferPointer: $0) }
        hasher.update(data: data)
    }

    private func update(_ value: UInt64, in hasher: inout SHA256) {
        var bigEndianValue = value.bigEndian
        withUnsafeBytes(of: &bigEndianValue) {
            hasher.update(bufferPointer: $0)
        }
    }

    private func hexadecimal(_ digest: SHA256.Digest) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var output: [UInt8] = []
        output.reserveCapacity(SHA256.byteCount * 2)
        for byte in digest {
            output.append(digits[Int(byte >> 4)])
            output.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: output, as: UTF8.self)
    }

    private func storageRelativePath(for fingerprint: Fingerprint) -> String {
        let payloadName = fingerprint.pathExtension.isEmpty
            ? "artifact"
            : "artifact.\(fingerprint.pathExtension)"
        return [
            "sha256",
            String(fingerprint.sha256Digest.prefix(2)),
            fingerprint.sha256Digest,
            payloadName
        ].joined(separator: "/")
    }

    private func validatedURL(for relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/")
        guard !relativePath.hasPrefix("/"),
              components.count == 4,
              components[0] == "sha256",
              components[1].count == 2,
              components[2].count == 64,
              components[3] == "artifact" || components[3].hasPrefix("artifact."),
              components[1].allSatisfy(\.isHexDigit),
              components[2].allSatisfy(\.isHexDigit) else {
            throw CoreAIArtifactStoreError.invalidStoredPath
        }
        let candidate = url(for: relativePath).standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path
        guard candidate.path.hasPrefix(rootPath + "/") else {
            throw CoreAIArtifactStoreError.invalidStoredPath
        }
        return candidate
    }
}

private extension CoreAIArtifactStore {
    struct Entry {
        let url: URL
        let relativePath: String
        let isDirectory: Bool
    }

    struct Fingerprint: Equatable {
        let sha256Digest: String
        let kind: CoreAIArtifactKind
        let pathExtension: String
        let byteCount: Int64
        let fileCount: Int
        let isDirectory: Bool

        func storedArtifact(
            relativePath: String,
            originalFilename: String,
            wasAlreadyStored: Bool
        ) -> CoreAIStoredArtifact {
            CoreAIStoredArtifact(
                sha256Digest: sha256Digest,
                storageRelativePath: relativePath,
                originalFilename: originalFilename,
                kind: kind,
                byteCount: byteCount,
                fileCount: fileCount,
                wasAlreadyStored: wasAlreadyStored
            )
        }
    }
}
