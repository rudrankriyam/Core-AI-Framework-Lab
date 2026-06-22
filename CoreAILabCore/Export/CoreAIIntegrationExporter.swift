import CryptoKit
import Darwin
import Foundation

enum CoreAIIntegrationExportError: LocalizedError, Equatable {
    case destinationExists(String)
    case destinationInsideSource
    case normalizedPathCollision(String)
    case sourceChanged(String)
    case symbolicLink(String)
    case unsupportedFile(String)

    var errorDescription: String? {
        switch self {
        case .destinationExists(let name):
            "An integration export named \(name) already exists in that folder."
        case .destinationInsideSource:
            "Choose a destination outside the source model asset."
        case .normalizedPathCollision(let path):
            "The model asset contains paths that collide after Unicode normalization: \(path)."
        case .sourceChanged(let path):
            "The model asset changed while it was being exported: \(path). Try the export again after writes finish."
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
    private let sourceSnapshotHook: @Sendable () throws -> Void
    private let compileScriptGenerator = CoreAIAheadOfTimeCompileScriptGenerator()
    private let packageGenerator = CoreAISwiftPackageGenerator()
    private let verifierScriptGenerator = CoreAIExportVerifierScriptGenerator()

    init(
        fileManager: FileManager = .default,
        generator: CoreAISwiftInvocationGenerator = CoreAISwiftInvocationGenerator(),
        sourceSnapshotHook: @escaping @Sendable () throws -> Void = {}
    ) {
        self.fileManager = fileManager
        self.generator = generator
        self.sourceSnapshotHook = sourceSnapshotHook
    }

    func export(
        report: CoreAIModelAssetReport,
        contracts: [CoreAIFunctionContract],
        specializationConfiguration: CoreAISpecializationConfiguration,
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

        let exportedAssetName = CoreAIExportPath.normalized(report.url.lastPathComponent)
        let generated = generator.generate(
            assetName: exportedAssetName,
            contracts: contracts,
            specializationConfiguration: specializationConfiguration
        )
        let packageName = generated.typeName + "Integration"
        let targetName = packageName
        let generatedPackage = packageGenerator.generate(
            packageName: packageName,
            targetName: targetName,
            modelTypeName: generated.typeName,
            assetName: exportedAssetName
        )
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
        let sourcesURL = temporaryURL.appending(path: "Sources", directoryHint: .isDirectory)
        let targetURL = sourcesURL.appending(path: targetName, directoryHint: .isDirectory)
        let resourcesURL = targetURL.appending(path: "Resources", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        try write(generatedPackage.packageManifest, to: temporaryURL.appending(path: "Package.swift"))

        let copiedAssetURL = resourcesURL.appending(
            path: exportedAssetName,
            directoryHint: .isDirectory
        )
        let digest = try copyAndHashTree(from: report.url, to: copiedAssetURL)
        try Task.checkCancellation()

        let sourceURL = targetURL.appending(path: generated.fileName)
        try write(generated.source, to: sourceURL)
        try write(
            generatedPackage.resourceAccessorSource,
            to: targetURL.appending(path: generatedPackage.resourceAccessorFileName)
        )
        let resourcesRelativePath = "Sources/\(targetName)/Resources"
        let generatedSourceRelativePath = "Sources/\(targetName)/\(generated.fileName)"
        let artifactPath = "\(resourcesRelativePath)/\(exportedAssetName)"
        let manifest = CoreAIExportManifest(
            package: CoreAIExportManifest.Package(
                name: packageName,
                productName: packageName,
                targetName: targetName,
                swiftToolsVersion: CoreAISwiftPackageGenerator.swiftToolsVersion,
                generatedSourceRelativePath: generatedSourceRelativePath,
                resourcesRelativePath: resourcesRelativePath
            ),
            artifact: CoreAIExportManifest.Artifact(
                relativePath: artifactPath,
                sha256: digest.sha256,
                byteCount: digest.byteCount
            ),
            report: report,
            specializationConfiguration: specializationConfiguration,
            contracts: contracts
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(
            to: resourcesURL.appending(path: "coreai-export.json"),
            options: .atomic
        )
        try write(
            thirdPartyNotices(report: report),
            to: resourcesURL.appending(path: "THIRD_PARTY_NOTICES.md")
        )
        try write(
            readme(report: report, generated: generated, manifest: manifest),
            to: temporaryURL.appending(path: "README.md")
        )
        let compileScriptURL = temporaryURL.appending(path: "compile-model.sh")
        let compileScript = compileScriptGenerator.generate(
            assetRelativePath: artifactPath,
            configuration: specializationConfiguration
        )
        try write(compileScript, to: compileScriptURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: compileScriptURL.path
        )
        let verifierScriptURL = temporaryURL.appending(path: "verify-export.py")
        try write(
            verifierScriptGenerator.generate(
                targetName: targetName,
                generatedSourceFileName: generated.fileName,
                resourceAccessorFileName: generatedPackage.resourceAccessorFileName,
                expectedPackageManifest: generatedPackage.packageManifest
            ),
            to: verifierScriptURL
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: verifierScriptURL.path
        )

        let checksumManifest = try makeChecksumManifest(in: temporaryURL)
        try encoder.encode(checksumManifest).write(
            to: temporaryURL.appending(path: "coreai-checksums.json"),
            options: .atomic
        )

        try Task.checkCancellation()
        try fileManager.moveItem(at: temporaryURL, to: finalURL)
        didFinish = true
        return CoreAIIntegrationExportResult(packageURL: finalURL, manifest: manifest)
    }

    private func makeChecksumManifest(
        in packageURL: URL
    ) throws -> CoreAIExportChecksumManifest {
        guard let enumerator = fileManager.enumerator(
            at: packageURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw CoreAIIntegrationExportError.unsupportedFile("export package")
        }
        let entries = enumerator.compactMap { $0 as? URL }.sorted {
            CoreAIExportPath.isOrderedBefore(
                CoreAIExportPath.normalized(relativePath(of: $0, under: packageURL)),
                CoreAIExportPath.normalized(relativePath(of: $1, under: packageURL))
            )
        }
        var files: [CoreAIExportChecksumManifest.File] = []
        var normalizedPaths: Set<String> = []
        for entry in entries {
            try Task.checkCancellation()
            let sourceRelativePath = relativePath(of: entry, under: packageURL)
            let relativePath = CoreAIExportPath.normalized(sourceRelativePath)
            guard normalizedPaths.insert(relativePath).inserted else {
                throw CoreAIIntegrationExportError.normalizedPathCollision(relativePath)
            }
            let values = try entry.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            if values.isSymbolicLink == true {
                throw CoreAIIntegrationExportError.symbolicLink(relativePath)
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                throw CoreAIIntegrationExportError.unsupportedFile(relativePath)
            }
            let digest = try hashFile(at: entry)
            files.append(
                CoreAIExportChecksumManifest.File(
                    relativePath: relativePath,
                    sha256: digest.digestData.hexString,
                    byteCount: digest.byteCount
                )
            )
        }
        return CoreAIExportChecksumManifest(files: files)
    }

    private func copyAndHashTree(from sourceURL: URL, to destinationURL: URL) throws -> TreeDigest {
        let rootDescriptor = try openRootDirectory(at: sourceURL)
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try identity(of: rootDescriptor)
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: false)

        guard let enumerator = fileManager.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw CoreAIIntegrationExportError.unsupportedFile(sourceURL.lastPathComponent)
        }
        var normalizedPaths: Set<String> = []
        var entries: [SourceEntry] = []
        for case let entry as URL in enumerator {
            let sourceRelativePath = relativePath(of: entry, under: sourceURL)
            let exportedRelativePath = CoreAIExportPath.normalized(sourceRelativePath)
            guard normalizedPaths.insert(exportedRelativePath).inserted else {
                throw CoreAIIntegrationExportError.normalizedPathCollision(exportedRelativePath)
            }
            entries.append(
                SourceEntry(
                    sourceRelativePath: sourceRelativePath,
                    exportedRelativePath: exportedRelativePath,
                    identity: try sourceIdentity(
                        relativePath: sourceRelativePath,
                        rootDescriptor: rootDescriptor
                    )
                )
            )
        }
        entries.sort {
            CoreAIExportPath.isOrderedBefore(
                $0.exportedRelativePath,
                $1.exportedRelativePath
            )
        }
        try sourceSnapshotHook()
        var treeHasher = SHA256()
        var totalByteCount: Int64 = 0

        for entry in entries {
            try Task.checkCancellation()
            let currentIdentity = try sourceIdentity(
                relativePath: entry.sourceRelativePath,
                rootDescriptor: rootDescriptor
            )
            guard currentIdentity == entry.identity else {
                throw CoreAIIntegrationExportError.sourceChanged(entry.sourceRelativePath)
            }
            let destination = destinationURL.appending(path: entry.exportedRelativePath)
            if entry.identity.isDirectory {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
                update(&treeHasher, with: "D\0\(entry.exportedRelativePath)\0")
            } else if entry.identity.isRegularFile {
                let fileDigest = try copyAndHashFile(
                    sourceRelativePath: entry.sourceRelativePath,
                    rootDescriptor: rootDescriptor,
                    expectedIdentity: entry.identity,
                    to: destination
                )
                totalByteCount += fileDigest.byteCount
                update(
                    &treeHasher,
                    with: "F\0\(entry.exportedRelativePath)\0\(fileDigest.byteCount)\0"
                )
                treeHasher.update(data: fileDigest.digestData)
            } else {
                throw CoreAIIntegrationExportError.unsupportedFile(entry.sourceRelativePath)
            }
        }

        for entry in entries {
            let finalIdentity = try sourceIdentity(
                relativePath: entry.sourceRelativePath,
                rootDescriptor: rootDescriptor
            )
            guard finalIdentity == entry.identity else {
                throw CoreAIIntegrationExportError.sourceChanged(entry.sourceRelativePath)
            }
        }
        guard try identity(of: rootDescriptor) == rootIdentity,
              try identity(at: sourceURL) == rootIdentity else {
            throw CoreAIIntegrationExportError.sourceChanged(sourceURL.lastPathComponent)
        }
        return TreeDigest(
            sha256: Data(treeHasher.finalize()).hexString,
            byteCount: totalByteCount
        )
    }

    private func copyAndHashFile(
        sourceRelativePath: String,
        rootDescriptor: Int32,
        expectedIdentity: SourceIdentity,
        to destinationURL: URL
    ) throws -> FileDigest {
        let openedSource = try openSourceEntry(
            relativePath: sourceRelativePath,
            rootDescriptor: rootDescriptor,
            expectedIdentity: expectedIdentity
        )
        defer {
            Darwin.close(openedSource.descriptor)
            Darwin.close(openedSource.parentDescriptor)
        }
        let outputDescriptor = destinationURL.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        }
        guard outputDescriptor >= 0 else {
            throw posixError()
        }
        defer { Darwin.close(outputDescriptor) }
        let digest = try readAndHash(
            descriptor: openedSource.descriptor,
            outputDescriptor: outputDescriptor
        )
        let descriptorIdentity = try identity(of: openedSource.descriptor)
        let pathIdentity = try identity(
            named: openedSource.leafName,
            in: openedSource.parentDescriptor,
            relativePath: sourceRelativePath
        )
        guard descriptorIdentity == expectedIdentity,
              pathIdentity == expectedIdentity,
              digest.byteCount == expectedIdentity.size else {
            throw CoreAIIntegrationExportError.sourceChanged(sourceRelativePath)
        }
        return digest
    }

    private func hashFile(at url: URL) throws -> FileDigest {
        let before = try identity(at: url)
        guard before.isRegularFile else {
            throw CoreAIIntegrationExportError.unsupportedFile(url.lastPathComponent)
        }
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            if errno == ELOOP {
                throw CoreAIIntegrationExportError.symbolicLink(url.lastPathComponent)
            }
            throw posixError()
        }
        defer { Darwin.close(descriptor) }
        guard try identity(of: descriptor) == before else {
            throw CoreAIIntegrationExportError.sourceChanged(url.lastPathComponent)
        }
        let digest = try readAndHash(descriptor: descriptor)
        guard try identity(of: descriptor) == before,
              try identity(at: url) == before,
              digest.byteCount == before.size else {
            throw CoreAIIntegrationExportError.sourceChanged(url.lastPathComponent)
        }
        return digest
    }

    private func readAndHash(
        descriptor: Int32,
        outputDescriptor: Int32? = nil
    ) throws -> FileDigest {
        var hasher = SHA256()
        var byteCount: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            let data = buffer.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return Data() }
                return Data(bytes: baseAddress, count: count)
            }
            if let outputDescriptor {
                try write(data, to: outputDescriptor)
            }
            hasher.update(data: data)
            byteCount += Int64(count)
        }
        return FileDigest(digestData: Data(hasher.finalize()), byteCount: byteCount)
    }

    private func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if count < 0 {
                    if errno == EINTR { continue }
                    throw posixError()
                }
                guard count > 0 else { throw POSIXError(.EIO) }
                offset += count
            }
        }
    }

    private func openRootDirectory(at url: URL) throws -> Int32 {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            if errno == ELOOP {
                throw CoreAIIntegrationExportError.symbolicLink(url.lastPathComponent)
            }
            throw posixError()
        }
        do {
            guard try identity(of: descriptor).isDirectory else {
                throw CoreAIIntegrationExportError.unsupportedFile(url.lastPathComponent)
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func sourceIdentity(
        relativePath: String,
        rootDescriptor: Int32
    ) throws -> SourceIdentity {
        let parent = try openParentDirectory(
            relativePath: relativePath,
            rootDescriptor: rootDescriptor
        )
        defer { Darwin.close(parent.descriptor) }
        let pathIdentity = try identity(
            named: parent.leafName,
            in: parent.descriptor,
            relativePath: relativePath
        )
        guard pathIdentity.isDirectory || pathIdentity.isRegularFile else {
            throw CoreAIIntegrationExportError.unsupportedFile(relativePath)
        }
        let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC
            | (pathIdentity.isDirectory ? O_DIRECTORY : 0)
        let descriptor = parent.leafName.withCString {
            Darwin.openat(parent.descriptor, $0, flags)
        }
        guard descriptor >= 0 else {
            if errno == ELOOP {
                throw CoreAIIntegrationExportError.symbolicLink(relativePath)
            }
            throw CoreAIIntegrationExportError.sourceChanged(relativePath)
        }
        defer { Darwin.close(descriptor) }
        let descriptorIdentity = try identity(of: descriptor)
        guard descriptorIdentity == pathIdentity else {
            throw CoreAIIntegrationExportError.sourceChanged(relativePath)
        }
        return descriptorIdentity
    }

    private func openSourceEntry(
        relativePath: String,
        rootDescriptor: Int32,
        expectedIdentity: SourceIdentity
    ) throws -> OpenedSourceEntry {
        let parent = try openParentDirectory(
            relativePath: relativePath,
            rootDescriptor: rootDescriptor
        )
        do {
            let pathIdentity = try identity(
                named: parent.leafName,
                in: parent.descriptor,
                relativePath: relativePath
            )
            guard pathIdentity == expectedIdentity, expectedIdentity.isRegularFile else {
                throw CoreAIIntegrationExportError.sourceChanged(relativePath)
            }
            let descriptor = parent.leafName.withCString {
                Darwin.openat(parent.descriptor, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            }
            guard descriptor >= 0 else {
                throw CoreAIIntegrationExportError.sourceChanged(relativePath)
            }
            do {
                guard try identity(of: descriptor) == expectedIdentity else {
                    throw CoreAIIntegrationExportError.sourceChanged(relativePath)
                }
                return OpenedSourceEntry(
                    descriptor: descriptor,
                    parentDescriptor: parent.descriptor,
                    leafName: parent.leafName
                )
            } catch {
                Darwin.close(descriptor)
                throw error
            }
        } catch {
            Darwin.close(parent.descriptor)
            throw error
        }
    }

    private func openParentDirectory(
        relativePath: String,
        rootDescriptor: Int32
    ) throws -> OpenedParentDirectory {
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard let leafName = components.last,
              !leafName.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw CoreAIIntegrationExportError.unsupportedFile(relativePath)
        }
        var descriptor = Darwin.dup(rootDescriptor)
        guard descriptor >= 0 else { throw posixError() }
        for component in components.dropLast() {
            let nextDescriptor = component.withCString {
                Darwin.openat(
                    descriptor,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            guard nextDescriptor >= 0 else {
                let errorNumber = errno
                Darwin.close(descriptor)
                if errorNumber == ELOOP {
                    throw CoreAIIntegrationExportError.symbolicLink(relativePath)
                }
                throw CoreAIIntegrationExportError.sourceChanged(relativePath)
            }
            Darwin.close(descriptor)
            descriptor = nextDescriptor
        }
        return OpenedParentDirectory(descriptor: descriptor, leafName: leafName)
    }

    private func identity(
        named name: String,
        in parentDescriptor: Int32,
        relativePath: String
    ) throws -> SourceIdentity {
        var fileStatus = stat()
        let result = name.withCString {
            Darwin.fstatat(parentDescriptor, $0, &fileStatus, AT_SYMLINK_NOFOLLOW)
        }
        guard result == 0 else {
            throw CoreAIIntegrationExportError.sourceChanged(relativePath)
        }
        let identity = SourceIdentity(fileStatus)
        if identity.isSymbolicLink {
            throw CoreAIIntegrationExportError.symbolicLink(relativePath)
        }
        return identity
    }

    private func identity(of descriptor: Int32) throws -> SourceIdentity {
        var fileStatus = stat()
        guard Darwin.fstat(descriptor, &fileStatus) == 0 else { throw posixError() }
        return SourceIdentity(fileStatus)
    }

    private func identity(at url: URL) throws -> SourceIdentity {
        var fileStatus = stat()
        let result = url.path.withCString { Darwin.lstat($0, &fileStatus) }
        guard result == 0 else {
            throw CoreAIIntegrationExportError.sourceChanged(url.lastPathComponent)
        }
        let identity = SourceIdentity(fileStatus)
        if identity.isSymbolicLink {
            throw CoreAIIntegrationExportError.symbolicLink(url.lastPathComponent)
        }
        return identity
    }

    private func posixError(_ errorNumber: Int32 = errno) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errorNumber) ?? .EIO)
    }

    private func write(_ value: String, to url: URL) throws {
        try Task.checkCancellation()
        try Data(value.utf8).write(to: url, options: .atomic)
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

            Generated by Core AI Lab from a standalone Core AI model asset. This directory is a dependency-free Swift package and does not reference Core AI Lab internals.

            - Asset: `\(report.url.lastPathComponent)`
            - SHA-256: `\(manifest.artifact.sha256)`
            - Generated NDArray functions: \(supported.count)
            - Manifest-only functions: \(unsupported.count)

            Add this directory as a local Swift package, import `\(manifest.package.productName)`, and call `try await \(generated.typeName).loadBundled()`. You can also pass another asset URL to `\(generated.typeName).load(from:)`.

            Run `python3 verify-export.py` to validate the resource inventory, checksums, manifest, generated source, and a clean local Swift build. It has no network dependencies and never runs `coreai-build`. Use `--structure-only` when the local Swift SDK cannot build Core AI packages.

            Run `./compile-model.sh` on a Mac to optionally create iOS and macOS ahead-of-time assets under `Compiled/`. The script is generated but never executed by Core AI Lab. Ahead-of-time output still requires device specialization.\(manifest.specialization.runtimeDefaultsToCPUOnly ? " Core AI's build tool has no CPU-only flag; the generated runtime defaults to `.cpuOnly`, which callers may explicitly override." : "")

            The generated runtime accepts caller-created `[String: NDArray]` inputs. It does not generate preprocessing, mutable-state orchestration, or semantic postprocessing.

            `Sources/\(manifest.package.targetName)/Resources/coreai-export.json` records the typed function contract and package metadata. The root `coreai-checksums.json` inventories every other package file, and `THIRD_PARTY_NOTICES.md` preserves the asset's reported author and license metadata.

            ## License

            Asset metadata reports: \(report.license.isEmpty ? "No license metadata. Review redistribution rights before sharing this package." : report.license)
            """ + "\n"
    }

    private func thirdPartyNotices(report: CoreAIModelAssetReport) -> String {
        let author = report.author.isEmpty ? "Not reported" : report.author
        let license = report.license.isEmpty ? "Not reported" : report.license
        return """
            # Third-Party Notices

            This generated package contains the Core AI asset `\(report.url.lastPathComponent)`.

            - Reported author: \(author)
            - Reported license: \(license)

            Core AI Lab reproduces metadata reported by the asset. It does not grant redistribution rights. Verify the upstream terms before distributing this package or its model weights.
            """ + "\n"
    }

    private struct TreeDigest {
        let sha256: String
        let byteCount: Int64
    }

    private struct SourceEntry {
        let sourceRelativePath: String
        let exportedRelativePath: String
        let identity: SourceIdentity
    }

    private struct SourceIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
        let mode: UInt32
        let size: Int64
        let modificationSeconds: Int64
        let modificationNanoseconds: Int64
        let statusChangeSeconds: Int64
        let statusChangeNanoseconds: Int64

        init(_ status: stat) {
            device = UInt64(bitPattern: Int64(status.st_dev))
            inode = UInt64(status.st_ino)
            mode = UInt32(status.st_mode)
            size = Int64(status.st_size)
            modificationSeconds = Int64(status.st_mtimespec.tv_sec)
            modificationNanoseconds = Int64(status.st_mtimespec.tv_nsec)
            statusChangeSeconds = Int64(status.st_ctimespec.tv_sec)
            statusChangeNanoseconds = Int64(status.st_ctimespec.tv_nsec)
        }

        var isDirectory: Bool {
            (mode & UInt32(S_IFMT)) == UInt32(S_IFDIR)
        }

        var isRegularFile: Bool {
            (mode & UInt32(S_IFMT)) == UInt32(S_IFREG)
        }

        var isSymbolicLink: Bool {
            (mode & UInt32(S_IFMT)) == UInt32(S_IFLNK)
        }
    }

    private struct OpenedParentDirectory {
        let descriptor: Int32
        let leafName: String
    }

    private struct OpenedSourceEntry {
        let descriptor: Int32
        let parentDescriptor: Int32
        let leafName: String
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
