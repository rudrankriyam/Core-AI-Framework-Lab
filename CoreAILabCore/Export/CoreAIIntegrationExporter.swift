import CryptoKit
import Foundation

enum CoreAIIntegrationExportError: LocalizedError, Equatable {
    case destinationExists(String)
    case destinationInsideSource
    case symbolicLink(String)
    case unsupportedFile(String)

    var errorDescription: String? {
        switch self {
        case .destinationExists(let name):
            "An integration export named \(name) already exists in that folder."
        case .destinationInsideSource:
            "Choose a destination outside the source model asset."
        case .symbolicLink(let path):
            "The model asset contains symbolic link \(path). Integration exports reject symbolic links."
        case .unsupportedFile(let path):
            "The model asset contains unsupported filesystem item \(path)."
        }
    }
}

struct CoreAIIntegrationExportResult: Equatable, Sendable {
    let packageURL: URL
    let manifest: CoreAIExportManifest
}

actor CoreAIIntegrationExporter {
    private let fileManager: FileManager
    private let generator: CoreAISwiftInvocationGenerator
    private let compileScriptGenerator = CoreAIAheadOfTimeCompileScriptGenerator()

    init(
        fileManager: FileManager = .default,
        generator: CoreAISwiftInvocationGenerator = CoreAISwiftInvocationGenerator()
    ) {
        self.fileManager = fileManager
        self.generator = generator
    }

    func export(
        report: CoreAIModelAssetReport,
        contracts: [CoreAIFunctionContract],
        specializationProfile: CoreAISpecializationProfile,
        expectFrequentReshapes: Bool = false,
        destinationParentURL: URL
    ) async throws -> CoreAIIntegrationExportResult {
        try Task.checkCancellation()
        let sourceAccess = report.url.startAccessingSecurityScopedResource()
        let destinationAccess = destinationParentURL.startAccessingSecurityScopedResource()
        defer {
            if sourceAccess { report.url.stopAccessingSecurityScopedResource() }
            if destinationAccess { destinationParentURL.stopAccessingSecurityScopedResource() }
        }
        let resolvedSourceURL = report.url.resolvingSymlinksInPath().standardizedFileURL
        let resolvedDestinationURL = destinationParentURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard !isSameOrDescendant(resolvedDestinationURL, of: resolvedSourceURL) else {
            throw CoreAIIntegrationExportError.destinationInsideSource
        }

        let generated = generator.generate(
            assetName: report.url.lastPathComponent,
            contracts: contracts,
            specializationProfile: specializationProfile,
            expectFrequentReshapes: expectFrequentReshapes
        )
        let packageName = generated.typeName + "Integration"
        let finalURL = destinationParentURL.appending(
            path: packageName,
            directoryHint: .isDirectory
        )
        guard !fileManager.fileExists(atPath: finalURL.path) else {
            throw CoreAIIntegrationExportError.destinationExists(packageName)
        }

        let temporaryURL = destinationParentURL.appending(
            path: ".\(packageName).tmp-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        var didFinish = false
        defer {
            if !didFinish {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: false)
        let resourcesURL = temporaryURL.appending(path: "Resources", directoryHint: .isDirectory)
        let sourcesURL = temporaryURL.appending(path: "Sources", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: false)
        try fileManager.createDirectory(at: sourcesURL, withIntermediateDirectories: false)

        let copiedAssetURL = resourcesURL.appending(
            path: report.url.lastPathComponent,
            directoryHint: .isDirectory
        )
        let digest = try copyAndHashTree(from: report.url, to: copiedAssetURL)
        try Task.checkCancellation()

        let sourceURL = sourcesURL.appending(path: generated.fileName)
        try Data(generated.source.utf8).write(to: sourceURL, options: .atomic)
        let artifactPath = "Resources/\(report.url.lastPathComponent)"
        let manifest = CoreAIExportManifest(
            artifact: CoreAIExportManifest.Artifact(
                relativePath: artifactPath,
                sha256: digest.sha256,
                byteCount: digest.byteCount
            ),
            report: report,
            specializationProfile: specializationProfile,
            expectFrequentReshapes: expectFrequentReshapes,
            contracts: contracts
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(
            to: temporaryURL.appending(path: "coreai-export.json"),
            options: .atomic
        )
        try Data(readme(report: report, generated: generated, manifest: manifest).utf8).write(
            to: temporaryURL.appending(path: "README.md"),
            options: .atomic
        )
        let compileScriptURL = temporaryURL.appending(path: "compile-model.sh")
        let compileScript = compileScriptGenerator.generate(
            assetRelativePath: artifactPath,
            profile: specializationProfile,
            expectFrequentReshapes: expectFrequentReshapes
        )
        try Data(compileScript.utf8).write(to: compileScriptURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: compileScriptURL.path
        )

        try Task.checkCancellation()
        try fileManager.moveItem(at: temporaryURL, to: finalURL)
        didFinish = true
        return CoreAIIntegrationExportResult(packageURL: finalURL, manifest: manifest)
    }

    private func copyAndHashTree(from sourceURL: URL, to destinationURL: URL) throws -> TreeDigest {
        let rootValues = try sourceURL.resourceValues(
            forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        if rootValues.isSymbolicLink == true {
            throw CoreAIIntegrationExportError.symbolicLink(sourceURL.lastPathComponent)
        }
        guard rootValues.isDirectory == true else {
            throw CoreAIIntegrationExportError.unsupportedFile(sourceURL.lastPathComponent)
        }
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: false)

        guard let enumerator = fileManager.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw CoreAIIntegrationExportError.unsupportedFile(sourceURL.lastPathComponent)
        }
        let entries = enumerator.compactMap { $0 as? URL }.sorted {
            relativePath(of: $0, under: sourceURL) < relativePath(of: $1, under: sourceURL)
        }
        var treeHasher = SHA256()
        var totalByteCount: Int64 = 0

        for entry in entries {
            try Task.checkCancellation()
            let relativePath = relativePath(of: entry, under: sourceURL)
            let values = try entry.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            if values.isSymbolicLink == true {
                throw CoreAIIntegrationExportError.symbolicLink(relativePath)
            }
            let destination = destinationURL.appending(path: relativePath)
            if values.isDirectory == true {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
                update(&treeHasher, with: "D\0\(relativePath)\0")
            } else if values.isRegularFile == true {
                let fileDigest = try copyAndHashFile(from: entry, to: destination)
                totalByteCount += fileDigest.byteCount
                update(&treeHasher, with: "F\0\(relativePath)\0\(fileDigest.byteCount)\0")
                treeHasher.update(data: fileDigest.digestData)
            } else {
                throw CoreAIIntegrationExportError.unsupportedFile(relativePath)
            }
        }
        return TreeDigest(
            sha256: Data(treeHasher.finalize()).hexString,
            byteCount: totalByteCount
        )
    }

    private func copyAndHashFile(from sourceURL: URL, to destinationURL: URL) throws -> FileDigest {
        fileManager.createFile(atPath: destinationURL.path, contents: nil)
        let input = try FileHandle(forReadingFrom: sourceURL)
        let output = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? input.close()
            try? output.close()
        }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: data)
            hasher.update(data: data)
            byteCount += Int64(data.count)
        }
        return FileDigest(digestData: Data(hasher.finalize()), byteCount: byteCount)
    }

    private func relativePath(of url: URL, under rootURL: URL) -> String {
        let root = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return String(path.dropFirst(root.count + 1))
    }

    private func isSameOrDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
    }

    private func update(_ hasher: inout SHA256, with value: String) {
        hasher.update(data: Data(value.utf8))
    }

    private func readme(
        report: CoreAIModelAssetReport,
        generated: CoreAISwiftInvocationGenerator.Output,
        manifest: CoreAIExportManifest
    ) -> String {
        let supported = manifest.functions.filter { $0.generatedRuntimeUnsupportedReason == nil }
        let unsupported = manifest.functions.filter { $0.generatedRuntimeUnsupportedReason != nil }
        return """
            # \(generated.typeName)

            Generated by Core AI Lab from a standalone Core AI model asset.

            - Asset: `\(report.url.lastPathComponent)`
            - SHA-256: `\(manifest.artifact.sha256)`
            - Generated NDArray functions: \(supported.count)
            - Manifest-only functions: \(unsupported.count)

            Add `Sources/\(generated.fileName)` to an iOS 27 or macOS 27 target, copy the asset from `Resources`, and pass its URL to `\(generated.typeName).load(from:)`.

            Run `./compile-model.sh` on a Mac to optionally create iOS and macOS ahead-of-time assets under `Compiled/`. The script is generated but never executed by Core AI Lab. Ahead-of-time output still requires device specialization.\(manifest.specialization.runtimeDefaultsToCPUOnly ? " Core AI's build tool has no CPU-only flag; the generated runtime defaults to `.cpuOnly`, which callers may explicitly override." : "")

            The generated runtime accepts caller-created `[String: NDArray]` inputs. It does not generate preprocessing, mutable-state orchestration, or semantic postprocessing.

            ## License

            Asset metadata reports: \(report.license.isEmpty ? "No license metadata. Review redistribution rights before sharing this package." : report.license)
            """ + "\n"
    }

    private struct TreeDigest {
        let sha256: String
        let byteCount: Int64
    }

    private struct FileDigest {
        let digestData: Data
        let byteCount: Int64
    }
}

private extension Data {
    var hexString: String {
        let digits = Array("0123456789abcdef".utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count * 2)
        for byte in self {
            bytes.append(digits[Int(byte >> 4)])
            bytes.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
