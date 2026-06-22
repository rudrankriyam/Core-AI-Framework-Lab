import CryptoKit
import Foundation

struct CoreAIStoredArtifact: Equatable, Sendable {
    let sourceURL: URL
    let sha256Digest: String
    let storageRelativePath: String
    let originalFilename: String
    let kind: CoreAIArtifactKind
    let byteCount: Int64
    let fileCount: Int
    let resourceSnapshot: CoreAIResourceFolderSnapshot?
    let wasAlreadyStored: Bool

    fileprivate init(
        sourceURL: URL,
        sha256Digest: String,
        storageRelativePath: String,
        originalFilename: String,
        kind: CoreAIArtifactKind,
        byteCount: Int64,
        fileCount: Int,
        resourceSnapshot: CoreAIResourceFolderSnapshot?,
        wasAlreadyStored: Bool
    ) {
        self.sourceURL = sourceURL
        self.sha256Digest = sha256Digest
        self.storageRelativePath = storageRelativePath
        self.originalFilename = originalFilename
        self.kind = kind
        self.byteCount = byteCount
        self.fileCount = fileCount
        self.resourceSnapshot = resourceSnapshot
        self.wasAlreadyStored = wasAlreadyStored
    }
}

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

        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let sourceFingerprint = try fingerprint(at: sourceURL)
        let relativePath = storageRelativePath(for: sourceFingerprint)
        let destinationURL = try validatedURL(
            for: relativePath,
            requireExisting: false
        )
        let destinationContainerURL = destinationURL.deletingLastPathComponent()

        if fileManager.fileExists(atPath: destinationContainerURL.path) {
            let existingURL = try validatedURL(
                for: relativePath,
                requireExisting: true
            )
            let storedFingerprint = try fingerprint(at: existingURL)
            guard storedFingerprint.sha256Digest == sourceFingerprint.sha256Digest else {
                throw CoreAIArtifactStoreError.corruptedStoredArtifact(
                    sourceFingerprint.sha256Digest
                )
            }
            return sourceFingerprint.storedArtifact(
                sourceURL: sourceURL,
                relativePath: relativePath,
                wasAlreadyStored: true
            )
        }

        let stagingIdentifier = UUID().uuidString
        let stagingParentURL = try CoreAIStoredPathSecurity.validatedDescendantURL(
            rootURL: rootURL,
            components: [".staging", stagingIdentifier],
            requireExisting: false
        )
        let stagedPayloadURL = stagingParentURL.appending(
            path: destinationURL.lastPathComponent,
            directoryHint: sourceFingerprint.isDirectory ? .isDirectory : .notDirectory
        )
        defer {
            try? CoreAIStoredPathSecurity.removeTree(
                rootURL: rootURL,
                parentComponents: [".staging"],
                entryName: stagingIdentifier
            )
        }

        try fileManager.createDirectory(
            at: stagingParentURL,
            withIntermediateDirectories: true
        )
        _ = try CoreAIStoredPathSecurity.validatedDescendantURL(
            rootURL: rootURL,
            components: [".staging", stagingIdentifier],
            requireExisting: true
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
        _ = try validatedURL(for: relativePath, requireExisting: false)
        do {
            _ = try CoreAIStoredPathSecurity.validatedDescendantURL(
                rootURL: rootURL,
                components: [".staging", stagingIdentifier],
                requireExisting: true
            )
            try fileManager.moveItem(
                at: stagingParentURL,
                to: destinationContainerURL
            )
        } catch {
            guard fileManager.fileExists(atPath: destinationURL.path) else {
                throw error
            }
            let existingURL = try validatedURL(
                for: relativePath,
                requireExisting: true
            )
            let storedFingerprint = try fingerprint(at: existingURL)
            guard storedFingerprint.sha256Digest == sourceFingerprint.sha256Digest else {
                throw CoreAIArtifactStoreError.corruptedStoredArtifact(
                    sourceFingerprint.sha256Digest
                )
            }
            return sourceFingerprint.storedArtifact(
                sourceURL: sourceURL,
                relativePath: relativePath,
                wasAlreadyStored: true
            )
        }

        return sourceFingerprint.storedArtifact(
            sourceURL: sourceURL,
            relativePath: relativePath,
            wasAlreadyStored: false
        )
    }

    func removeArtifact(at relativePath: String) throws {
        try CoreAIStoredPathSecurity.removeContentAddressedContainer(
            rootURL: rootURL,
            relativePath: relativePath
        )
    }

    nonisolated func validatedURL(
        for relativePath: String,
        requireExisting: Bool = true
    ) throws -> URL {
        try CoreAIStoredPathSecurity.validatedURL(
            rootURL: rootURL,
            relativePath: relativePath,
            requireExisting: requireExisting
        )
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
        var resourceDirectories: [String] = []
        var resourceFiles: [CoreAIResourceFileSnapshot] = []
        if isDirectory {
            let entries = try entries(in: sourceURL)
            for entry in entries {
                try Task.checkCancellation()
                update(entry.isDirectory ? "directory" : "file", in: &hasher)
                update(entry.relativePath, in: &hasher)
                if entry.isDirectory {
                    resourceDirectories.append(entry.relativePath)
                } else {
                    let fileFingerprint = try addFile(
                        at: entry.url,
                        to: &hasher
                    )
                    let (updatedByteCount, overflow) = byteCount.addingReportingOverflow(
                        fileFingerprint.byteCount
                    )
                    guard !overflow else {
                        throw CoreAIArtifactStoreError.unsupportedItem(
                            entry.relativePath
                        )
                    }
                    byteCount = updatedByteCount
                    fileCount += 1
                    resourceFiles.append(
                        CoreAIResourceFileSnapshot(
                            relativePath: entry.relativePath,
                            sha256Digest: fileFingerprint.sha256Digest,
                            byteCount: fileFingerprint.byteCount
                        )
                    )
                }
            }
        } else {
            update("file", in: &hasher)
            byteCount = try addFile(
                at: sourceURL,
                to: &hasher
            ).byteCount
            fileCount = 1
        }

        let resourceSnapshot: CoreAIResourceFolderSnapshot? = if isDirectory {
            CoreAIResourceFolderSnapshot(
                directories: resourceDirectories,
                files: resourceFiles
            )
        } else {
            nil
        }
        try resourceSnapshot?.validate()

        return Fingerprint(
            sha256Digest: CoreAIHexadecimal.lowercase(hasher.finalize()),
            kind: kind,
            pathExtension: pathExtension,
            byteCount: byteCount,
            fileCount: fileCount,
            isDirectory: isDirectory,
            resourceSnapshot: resourceSnapshot
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
        var comparisonPaths = Set<String>()
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
            do {
                try CoreAIManifestValidator.requireSafeRelativePath(
                    relativePath,
                    path: "resourceFolder"
                )
            } catch {
                throw CoreAIArtifactStoreError.unsafeRelativePath(relativePath)
            }
            guard !relativePath.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            }) else {
                throw CoreAIArtifactStoreError.unsafeRelativePath(relativePath)
            }
            let comparisonPath = relativePath.lowercased()
            guard comparisonPaths.insert(comparisonPath).inserted else {
                throw CoreAIArtifactStoreError.unsafeRelativePath(relativePath)
            }
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
        to hasher: inout SHA256
    ) throws -> FileFingerprint {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let expectedByteCount = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        update(expectedByteCount, in: &hasher)
        var fileHasher = SHA256()
        var fileByteCount: UInt64 = 0
        while let chunk = try handle.read(upToCount: readChunkSize), !chunk.isEmpty {
            try Task.checkCancellation()
            let (nextFileByteCount, fileOverflow) = fileByteCount.addingReportingOverflow(
                UInt64(chunk.count)
            )
            guard !fileOverflow else {
                throw CoreAIArtifactStoreError.unsupportedItem(url.lastPathComponent)
            }
            fileByteCount = nextFileByteCount
            hasher.update(data: chunk)
            fileHasher.update(data: chunk)
        }
        guard fileByteCount == expectedByteCount else {
            throw CoreAIArtifactStoreError.sourceChangedDuringImport
        }
        guard let byteCount = Int64(exactly: fileByteCount) else {
            throw CoreAIArtifactStoreError.unsupportedItem(url.lastPathComponent)
        }
        return FileFingerprint(
            byteCount: byteCount,
            sha256Digest: CoreAIHexadecimal.lowercase(fileHasher.finalize())
        )
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
        let resourceSnapshot: CoreAIResourceFolderSnapshot?

        func storedArtifact(
            sourceURL: URL,
            relativePath: String,
            wasAlreadyStored: Bool
        ) -> CoreAIStoredArtifact {
            CoreAIStoredArtifact(
                sourceURL: sourceURL,
                sha256Digest: sha256Digest,
                storageRelativePath: relativePath,
                originalFilename: sourceURL.lastPathComponent,
                kind: kind,
                byteCount: byteCount,
                fileCount: fileCount,
                resourceSnapshot: resourceSnapshot,
                wasAlreadyStored: wasAlreadyStored
            )
        }
    }

    struct FileFingerprint {
        let byteCount: Int64
        let sha256Digest: String
    }
}
