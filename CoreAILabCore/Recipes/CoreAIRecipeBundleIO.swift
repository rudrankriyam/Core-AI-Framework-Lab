import CryptoKit
import Foundation

public struct CoreAIRecipeBundleDraftFile: Equatable, Sendable {
    public let relativePath: String
    public let role: CoreAIRecipeBundleFileRole

    public init(relativePath: String, role: CoreAIRecipeBundleFileRole) {
        self.relativePath = relativePath
        self.role = role
    }
}

public struct CoreAIRecipeBundleDraft: Equatable, Sendable {
    public let sourceRootURL: URL
    public let id: String
    public let familyID: String
    public let revision: String
    public let displayName: String
    public let summary: String
    public let recipeManifestPath: String
    public let provenance: CoreAIRecipeBundleProvenance
    public let files: [CoreAIRecipeBundleDraftFile]
    public let codeReferences: [CoreAIRecipeCodeReference]

    public init(
        sourceRootURL: URL,
        id: String,
        familyID: String,
        revision: String,
        displayName: String,
        summary: String,
        recipeManifestPath: String,
        provenance: CoreAIRecipeBundleProvenance,
        files: [CoreAIRecipeBundleDraftFile],
        codeReferences: [CoreAIRecipeCodeReference] = []
    ) {
        self.sourceRootURL = sourceRootURL
        self.id = id
        self.familyID = familyID
        self.revision = revision
        self.displayName = displayName
        self.summary = summary
        self.recipeManifestPath = recipeManifestPath
        self.provenance = provenance
        self.files = files
        self.codeReferences = codeReferences
    }
}

public struct CoreAIRecipeBundleExportResult: Equatable, Sendable {
    public let bundleURL: URL
    public let manifest: CoreAIRecipeBundleManifest
    public let manifestSHA256: String

    public init(
        bundleURL: URL,
        manifest: CoreAIRecipeBundleManifest,
        manifestSHA256: String
    ) {
        self.bundleURL = bundleURL
        self.manifest = manifest
        self.manifestSHA256 = manifestSHA256
    }
}

public enum CoreAIRecipeCodeApprovalState: String, Codable, Equatable, Sendable {
    case notRequired
    case approvalRequired
    case approved
}

public struct CoreAIImportedRecipeBundleSummary: Equatable, Sendable {
    public let manifest: CoreAIRecipeBundleManifest
    public let manifestSHA256: String
    public let trustState: CoreAIRecipeTrustState

    public init(
        manifest: CoreAIRecipeBundleManifest,
        manifestSHA256: String,
        trustState: CoreAIRecipeTrustState
    ) {
        self.manifest = manifest
        self.manifestSHA256 = manifestSHA256
        self.trustState = trustState
    }
}

public actor CoreAIRecipeBundleSession {
    public nonisolated let summary: CoreAIImportedRecipeBundleSummary

    private let bundleRootURL: URL
    private var isCodeExecutionApproved = false

    init(
        bundleRootURL: URL,
        manifest: CoreAIRecipeBundleManifest,
        manifestSHA256: String
    ) {
        self.bundleRootURL = bundleRootURL
        summary = CoreAIImportedRecipeBundleSummary(
            manifest: manifest,
            manifestSHA256: manifestSHA256,
            trustState: .importedUntrusted
        )
    }

    public var codeApprovalState: CoreAIRecipeCodeApprovalState {
        if summary.manifest.codeReferences.isEmpty {
            return .notRequired
        }
        return isCodeExecutionApproved ? .approved : .approvalRequired
    }

    public func approveReferencedCodeExecution() {
        guard !summary.manifest.codeReferences.isEmpty else { return }
        isCodeExecutionApproved = true
    }

    public func revokeReferencedCodeExecutionApproval() {
        isCodeExecutionApproved = false
    }

    public func payloadURL(for relativePath: String) throws -> URL {
        guard let payload = summary.manifest.files.first(where: {
            $0.relativePath == relativePath
        }) else {
            throw CoreAIRecipeBundleError.missingPayload(relativePath)
        }
        if payload.role.requiresExecutionApproval && !isCodeExecutionApproved {
            let referenceID = summary.manifest.codeReferences.first(where: {
                $0.relativePath == relativePath
            })?.id ?? relativePath
            throw CoreAIRecipeBundleError.codeExecutionNotApproved(
                referenceID: referenceID
            )
        }
        return try CoreAIRecipeBundleFileSystem.verifiedPayloadURL(
            rootURL: bundleRootURL,
            file: payload
        )
    }

    public func authorizedCodeURL(for referenceID: String) throws -> URL {
        guard let reference = summary.manifest.codeReferences.first(where: {
            $0.id == referenceID
        }) else {
            throw CoreAIRecipeBundleError.unknownCodeReference(path: referenceID)
        }
        guard isCodeExecutionApproved else {
            throw CoreAIRecipeBundleError.codeExecutionNotApproved(
                referenceID: referenceID
            )
        }
        return try payloadURL(for: reference.relativePath)
    }
}

public actor CoreAIRecipeBundleExporter {
    public init() {}

    public func export(
        _ draft: CoreAIRecipeBundleDraft,
        to destinationURL: URL
    ) throws -> CoreAIRecipeBundleExportResult {
        try Task.checkCancellation()
        try CoreAIRecipeBundleFileSystem.validateRootDirectory(draft.sourceRootURL)
        let sourcePath = draft.sourceRootURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let destinationPath = destinationURL.standardizedFileURL.path
        guard destinationPath != sourcePath,
              !destinationPath.hasPrefix(sourcePath + "/") else {
            throw CoreAIRecipeBundleError.destinationInsideSource
        }
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw CoreAIRecipeBundleError.destinationExists(destinationURL.path)
        }

        let destinationParentURL = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: destinationParentURL,
            withIntermediateDirectories: true
        )
        try CoreAIRecipeBundleFileSystem.validateRootDirectory(
            destinationParentURL
        )
        let resolvedDestinationPath = destinationParentURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .appending(path: destinationURL.lastPathComponent)
            .path
        guard resolvedDestinationPath != sourcePath,
              !resolvedDestinationPath.hasPrefix(sourcePath + "/") else {
            throw CoreAIRecipeBundleError.destinationInsideSource
        }
        let stagingURL = destinationParentURL.appending(
            path: ".recipe-export-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: stagingURL) }
        try FileManager.default.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: false
        )

        var manifestFiles: [CoreAIRecipeBundleFile] = []
        let draftFiles = draft.files.sorted { $0.relativePath < $1.relativePath }
        for draftFile in draftFiles {
            try Task.checkCancellation()
            try CoreAIRecipeBundleValidation.requireSafeRelativePath(
                draftFile.relativePath,
                path: "draft.files.relativePath"
            )
            let sourceURL = try CoreAIRecipeBundleFileSystem.validatedPayloadURL(
                rootURL: draft.sourceRootURL,
                relativePath: draftFile.relativePath
            )
            try CoreAIRecipeBundleFileSystem.validateDeclaredRole(
                draftFile.role,
                payloadURL: sourceURL,
                relativePath: draftFile.relativePath
            )
            let destinationPayloadURL = CoreAIRecipeBundleFileSystem.url(
                rootURL: stagingURL,
                relativePath: draftFile.relativePath
            )
            try FileManager.default.createDirectory(
                at: destinationPayloadURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let fingerprint = try CoreAIRecipeBundleFileSystem.copyAndFingerprint(
                from: sourceURL,
                to: destinationPayloadURL,
                relativePath: draftFile.relativePath
            )
            manifestFiles.append(
                CoreAIRecipeBundleFile(
                    relativePath: draftFile.relativePath,
                    sha256: fingerprint.sha256,
                    byteCount: fingerprint.byteCount,
                    role: draftFile.role
                )
            )
        }

        let manifest = CoreAIRecipeBundleManifest(
            id: draft.id,
            familyID: draft.familyID,
            revision: draft.revision,
            displayName: draft.displayName,
            summary: draft.summary,
            recipeManifestPath: draft.recipeManifestPath,
            provenance: draft.provenance,
            files: manifestFiles.sorted { $0.relativePath < $1.relativePath },
            codeReferences: draft.codeReferences.sorted { $0.id < $1.id }
        )
        try manifest.validate()
        let manifestData = try CoreAIRecipeBundleFileSystem.canonicalManifestData(
            manifest
        )
        try manifestData.write(
            to: stagingURL.appending(path: CoreAIRecipeBundleManifest.fileName),
            options: .atomic
        )

        let inspection = try CoreAIRecipeBundleFileSystem.inspectBundle(
            at: stagingURL,
            expectedFamilyID: draft.familyID
        )
        try FileManager.default.moveItem(at: stagingURL, to: destinationURL)
        return CoreAIRecipeBundleExportResult(
            bundleURL: destinationURL,
            manifest: inspection.manifest,
            manifestSHA256: inspection.manifestSHA256
        )
    }
}

public actor CoreAIRecipeBundleImporter {
    private let managedRootURL: URL

    public init(managedRootURL: URL) {
        self.managedRootURL = managedRootURL
    }

    public func importBundle(
        at sourceURL: URL,
        expectedFamilyID: String? = nil
    ) throws -> CoreAIRecipeBundleSession {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try Task.checkCancellation()
        let sourceInspection = try CoreAIRecipeBundleFileSystem.inspectBundle(
            at: sourceURL,
            expectedFamilyID: expectedFamilyID
        )
        try CoreAIRecipeBundleFileSystem.ensureManagedRoot(managedRootURL)

        let destinationURL = managedRootURL.appending(
            path: sourceInspection.manifestSHA256,
            directoryHint: .isDirectory
        )
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let storedInspection = try CoreAIRecipeBundleFileSystem.inspectBundle(
                at: destinationURL,
                expectedFamilyID: expectedFamilyID
            )
            guard storedInspection.manifestSHA256 == sourceInspection.manifestSHA256 else {
                throw CoreAIRecipeBundleError.hashMismatch(
                    path: CoreAIRecipeBundleManifest.fileName,
                    expected: sourceInspection.manifestSHA256,
                    actual: storedInspection.manifestSHA256
                )
            }
            return CoreAIRecipeBundleSession(
                bundleRootURL: destinationURL,
                manifest: storedInspection.manifest,
                manifestSHA256: storedInspection.manifestSHA256
            )
        }

        let stagingParentURL = managedRootURL.appending(
            path: ".staging",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: stagingParentURL,
            withIntermediateDirectories: true
        )
        try CoreAIRecipeBundleFileSystem.validateRootDirectory(stagingParentURL)
        let stagingURL = stagingParentURL.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: stagingURL) }
        try FileManager.default.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: false
        )

        for file in sourceInspection.manifest.files.sorted(by: {
            $0.relativePath < $1.relativePath
        }) {
            try Task.checkCancellation()
            let sourcePayloadURL = try CoreAIRecipeBundleFileSystem.validatedPayloadURL(
                rootURL: sourceURL,
                relativePath: file.relativePath
            )
            let stagedPayloadURL = CoreAIRecipeBundleFileSystem.url(
                rootURL: stagingURL,
                relativePath: file.relativePath
            )
            try FileManager.default.createDirectory(
                at: stagedPayloadURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let copiedFingerprint = try CoreAIRecipeBundleFileSystem.copyAndFingerprint(
                from: sourcePayloadURL,
                to: stagedPayloadURL,
                relativePath: file.relativePath
            )
            guard copiedFingerprint.sha256 == file.sha256 else {
                throw CoreAIRecipeBundleError.hashMismatch(
                    path: file.relativePath,
                    expected: file.sha256,
                    actual: copiedFingerprint.sha256
                )
            }
            guard copiedFingerprint.byteCount == file.byteCount else {
                throw CoreAIRecipeBundleError.sizeMismatch(
                    path: file.relativePath,
                    expected: file.byteCount,
                    actual: copiedFingerprint.byteCount
                )
            }
        }

        try sourceInspection.canonicalManifestData.write(
            to: stagingURL.appending(path: CoreAIRecipeBundleManifest.fileName),
            options: .atomic
        )
        let stagedInspection = try CoreAIRecipeBundleFileSystem.inspectBundle(
            at: stagingURL,
            expectedFamilyID: expectedFamilyID
        )
        guard stagedInspection.manifestSHA256 == sourceInspection.manifestSHA256 else {
            throw CoreAIRecipeBundleError.hashMismatch(
                path: CoreAIRecipeBundleManifest.fileName,
                expected: sourceInspection.manifestSHA256,
                actual: stagedInspection.manifestSHA256
            )
        }

        do {
            try FileManager.default.moveItem(at: stagingURL, to: destinationURL)
        } catch {
            guard FileManager.default.fileExists(atPath: destinationURL.path) else {
                throw error
            }
            let storedInspection = try CoreAIRecipeBundleFileSystem.inspectBundle(
                at: destinationURL,
                expectedFamilyID: expectedFamilyID
            )
            guard storedInspection.manifestSHA256 == sourceInspection.manifestSHA256 else {
                throw error
            }
        }

        return CoreAIRecipeBundleSession(
            bundleRootURL: destinationURL,
            manifest: stagedInspection.manifest,
            manifestSHA256: stagedInspection.manifestSHA256
        )
    }
}

private struct CoreAIRecipeBundleFingerprint: Equatable {
    let sha256: String
    let byteCount: Int64
}

private struct CoreAIRecipeBundleInspection {
    let manifest: CoreAIRecipeBundleManifest
    let manifestSHA256: String
    let canonicalManifestData: Data
}

private enum CoreAIRecipeBundleFileSystem {
    private static let readChunkSize = 1_048_576
    private static let maximumManifestByteCount = 4_194_304

    static func inspectBundle(
        at rootURL: URL,
        expectedFamilyID: String?
    ) throws -> CoreAIRecipeBundleInspection {
        try validateRootDirectory(rootURL)
        let manifestURL = try validatedPayloadURL(
            rootURL: rootURL,
            relativePath: CoreAIRecipeBundleManifest.fileName
        )
        let manifestValues = try manifestURL.resourceValues(forKeys: [.fileSizeKey])
        guard let manifestSize = manifestValues.fileSize,
              manifestSize <= maximumManifestByteCount else {
            throw CoreAIRecipeBundleError.unsupportedPayload(
                CoreAIRecipeBundleManifest.fileName
            )
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(
            CoreAIRecipeBundleManifest.self,
            from: manifestData
        )
        try manifest.validate()
        if let expectedFamilyID, manifest.familyID != expectedFamilyID {
            throw CoreAIRecipeBundleError.familyMismatch(
                expected: expectedFamilyID,
                actual: manifest.familyID
            )
        }

        let actualFiles = try regularFiles(in: rootURL)
        let expectedFiles = Set(
            manifest.files.map(\.relativePath) + [CoreAIRecipeBundleManifest.fileName]
        )
        if let missingPath = expectedFiles.subtracting(actualFiles).sorted().first {
            throw CoreAIRecipeBundleError.missingPayload(missingPath)
        }
        if let unexpectedPath = actualFiles.subtracting(expectedFiles).sorted().first {
            throw CoreAIRecipeBundleError.unexpectedPayload(unexpectedPath)
        }

        for file in manifest.files.sorted(by: { $0.relativePath < $1.relativePath }) {
            try Task.checkCancellation()
            let payloadURL = try validatedPayloadURL(
                rootURL: rootURL,
                relativePath: file.relativePath
            )
            try validateDeclaredRole(
                file.role,
                payloadURL: payloadURL,
                relativePath: file.relativePath
            )
            let fingerprint = try fingerprint(at: payloadURL)
            guard fingerprint.sha256 == file.sha256 else {
                throw CoreAIRecipeBundleError.hashMismatch(
                    path: file.relativePath,
                    expected: file.sha256,
                    actual: fingerprint.sha256
                )
            }
            guard fingerprint.byteCount == file.byteCount else {
                throw CoreAIRecipeBundleError.sizeMismatch(
                    path: file.relativePath,
                    expected: file.byteCount,
                    actual: fingerprint.byteCount
                )
            }
        }

        let canonicalData = try canonicalManifestData(manifest)
        return CoreAIRecipeBundleInspection(
            manifest: manifest,
            manifestSHA256: CoreAIHexadecimal.lowercase(
                SHA256.hash(data: canonicalData)
            ),
            canonicalManifestData: canonicalData
        )
    }

    static func validateRootDirectory(_ rootURL: URL) throws {
        let values = try rootURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        if values.isSymbolicLink == true {
            throw CoreAIRecipeBundleError.symbolicLink(".")
        }
        guard values.isDirectory == true else {
            throw CoreAIRecipeBundleError.unsupportedPayload(rootURL.lastPathComponent)
        }
    }

    static func ensureManagedRoot(_ rootURL: URL) throws {
        if FileManager.default.fileExists(atPath: rootURL.path) {
            try validateRootDirectory(rootURL)
            return
        }
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        try validateRootDirectory(rootURL)
    }

    static func validatedPayloadURL(
        rootURL: URL,
        relativePath: String
    ) throws -> URL {
        try CoreAIRecipeBundleValidation.requireSafeRelativePath(
            relativePath,
            path: "payload.relativePath"
        )
        try validateRootDirectory(rootURL)
        let components = relativePath.split(separator: "/").map(String.init)
        var currentURL = rootURL
        for (index, component) in components.enumerated() {
            currentURL.append(path: component)
            let values = try currentURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            if values.isSymbolicLink == true {
                throw CoreAIRecipeBundleError.symbolicLink(
                    components.prefix(index + 1).joined(separator: "/")
                )
            }
            if index < components.count - 1 {
                guard values.isDirectory == true else {
                    throw CoreAIRecipeBundleError.unsupportedPayload(
                        components.prefix(index + 1).joined(separator: "/")
                    )
                }
            } else if values.isRegularFile != true {
                throw CoreAIRecipeBundleError.unsupportedPayload(relativePath)
            }
        }
        let rootPath = rootURL.standardizedFileURL.path
        let payloadPath = currentURL.standardizedFileURL.path
        guard payloadPath.hasPrefix(rootPath + "/") else {
            throw CoreAIRecipeBundleError.invalidRelativePath(
                path: "payload.relativePath",
                value: relativePath
            )
        }
        return currentURL
    }

    static func verifiedPayloadURL(
        rootURL: URL,
        file: CoreAIRecipeBundleFile
    ) throws -> URL {
        let payloadURL = try validatedPayloadURL(
            rootURL: rootURL,
            relativePath: file.relativePath
        )
        let currentFingerprint = try fingerprint(at: payloadURL)
        guard currentFingerprint.sha256 == file.sha256 else {
            throw CoreAIRecipeBundleError.hashMismatch(
                path: file.relativePath,
                expected: file.sha256,
                actual: currentFingerprint.sha256
            )
        }
        guard currentFingerprint.byteCount == file.byteCount else {
            throw CoreAIRecipeBundleError.sizeMismatch(
                path: file.relativePath,
                expected: file.byteCount,
                actual: currentFingerprint.byteCount
            )
        }
        return payloadURL
    }

    static func url(rootURL: URL, relativePath: String) -> URL {
        relativePath.split(separator: "/").reduce(rootURL) { partialURL, component in
            partialURL.appending(path: String(component))
        }
    }

    static func canonicalManifestData(
        _ manifest: CoreAIRecipeBundleManifest
    ) throws -> Data {
        let canonicalManifest = CoreAIRecipeBundleManifest(
            schemaVersion: manifest.schemaVersion,
            id: manifest.id,
            familyID: manifest.familyID,
            revision: manifest.revision,
            displayName: manifest.displayName,
            summary: manifest.summary,
            recipeManifestPath: manifest.recipeManifestPath,
            provenance: manifest.provenance,
            files: manifest.files.sorted { $0.relativePath < $1.relativePath },
            codeReferences: manifest.codeReferences.sorted { $0.id < $1.id }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(canonicalManifest)
        data.append(0x0A)
        return data
    }

    static func validateDeclaredRole(
        _ role: CoreAIRecipeBundleFileRole,
        payloadURL: URL,
        relativePath: String
    ) throws {
        guard !role.requiresExecutionApproval else { return }
        if FileManager.default.isExecutableFile(atPath: payloadURL.path) {
            throw CoreAIRecipeBundleError.hiddenCodeReference(path: relativePath)
        }

        let handle = try FileHandle(forReadingFrom: payloadURL)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 8) ?? Data()
        let executableMagic: [[UInt8]] = [
            [0x23, 0x21],
            [0x7f, 0x45, 0x4c, 0x46],
            [0x00, 0x61, 0x73, 0x6d],
            [0xfe, 0xed, 0xfa, 0xce],
            [0xce, 0xfa, 0xed, 0xfe],
            [0xfe, 0xed, 0xfa, 0xcf],
            [0xcf, 0xfa, 0xed, 0xfe],
            [0xca, 0xfe, 0xba, 0xbe],
            [0xbe, 0xba, 0xfe, 0xca],
            [0xca, 0xfe, 0xba, 0xbf],
            [0xbf, 0xba, 0xfe, 0xca]
        ]
        if executableMagic.contains(where: { prefix.starts(with: $0) }) {
            throw CoreAIRecipeBundleError.hiddenCodeReference(path: relativePath)
        }
    }

    static func copyAndFingerprint(
        from sourceURL: URL,
        to destinationURL: URL,
        relativePath: String
    ) throws -> CoreAIRecipeBundleFingerprint {
        let before = try sourceURL.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        )
        guard before.isRegularFile == true else {
            throw CoreAIRecipeBundleError.unsupportedPayload(relativePath)
        }
        _ = FileManager.default.createFile(
            atPath: destinationURL.path,
            contents: nil
        )
        let input = try FileHandle(forReadingFrom: sourceURL)
        let output = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? input.close()
            try? output.close()
        }

        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let chunk = try input.read(upToCount: readChunkSize), !chunk.isEmpty {
            try Task.checkCancellation()
            let (nextByteCount, overflow) = byteCount.addingReportingOverflow(
                Int64(chunk.count)
            )
            guard !overflow else {
                throw CoreAIRecipeBundleError.unsupportedPayload(relativePath)
            }
            byteCount = nextByteCount
            hasher.update(data: chunk)
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()

        let after = try sourceURL.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        )
        guard before.fileSize == after.fileSize,
              before.contentModificationDate == after.contentModificationDate,
              before.fileSize == Int(byteCount) else {
            throw CoreAIRecipeBundleError.sourceChangedDuringExport(relativePath)
        }
        return CoreAIRecipeBundleFingerprint(
            sha256: CoreAIHexadecimal.lowercase(hasher.finalize()),
            byteCount: byteCount
        )
    }

    private static func fingerprint(at url: URL) throws -> CoreAIRecipeBundleFingerprint {
        let values = try url.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        if values.isSymbolicLink == true {
            throw CoreAIRecipeBundleError.symbolicLink(url.lastPathComponent)
        }
        guard values.isRegularFile == true else {
            throw CoreAIRecipeBundleError.unsupportedPayload(url.lastPathComponent)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let chunk = try handle.read(upToCount: readChunkSize), !chunk.isEmpty {
            try Task.checkCancellation()
            let (nextByteCount, overflow) = byteCount.addingReportingOverflow(
                Int64(chunk.count)
            )
            guard !overflow else {
                throw CoreAIRecipeBundleError.unsupportedPayload(url.lastPathComponent)
            }
            byteCount = nextByteCount
            hasher.update(data: chunk)
        }
        guard values.fileSize == Int(byteCount) else {
            throw CoreAIRecipeBundleError.sourceChangedDuringExport(
                url.lastPathComponent
            )
        }
        return CoreAIRecipeBundleFingerprint(
            sha256: CoreAIHexadecimal.lowercase(hasher.finalize()),
            byteCount: byteCount
        )
    }

    private static func regularFiles(in rootURL: URL) throws -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ]
        ) else {
            throw CoreAIRecipeBundleError.unsupportedPayload(rootURL.lastPathComponent)
        }

        let rootPath = rootURL.standardizedFileURL.path
        var paths = Set<String>()
        for case let childURL as URL in enumerator {
            let values = try childURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            let childPath = childURL.standardizedFileURL.path
            guard childPath.hasPrefix(rootPath + "/") else {
                throw CoreAIRecipeBundleError.invalidRelativePath(
                    path: "bundle",
                    value: childPath
                )
            }
            let relativePath = String(childPath.dropFirst(rootPath.count + 1))
                .precomposedStringWithCanonicalMapping
            if values.isSymbolicLink == true {
                throw CoreAIRecipeBundleError.symbolicLink(relativePath)
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                throw CoreAIRecipeBundleError.unsupportedPayload(relativePath)
            }
            paths.insert(relativePath)
        }
        return paths
    }

}
