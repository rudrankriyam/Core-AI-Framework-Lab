import Foundation

struct ChatterboxBundledRecipe: Sendable {
    let rootURL: URL
    let contract: ChatterboxRecipeContract
    let tokenizerURL: URL
    private let artifactURLsByID: [String: URL]

    init(bundle: Bundle) throws {
        guard let rootURL = bundle.url(
            forResource: "Chatterbox",
            withExtension: nil
        ) else {
            throw ChatterboxCoreAIError.bundledResourcesMissing
        }
        try self.init(rootURL: rootURL)
    }

    init(rootURL: URL) throws {
        let rootURL = rootURL.standardizedFileURL
        guard try rootURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink
            != true else {
            throw ChatterboxCoreAIError.unsafeResourcePath(rootURL.path)
        }
        let manifestURL = try Self.validatedArtifactURL(
            rootURL: rootURL,
            relativePath: "recipe.json"
        )
        let manifest = try JSONDecoder().decode(
            CoreAIRecipeManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let contract = try ChatterboxRecipeContract(manifest: manifest)

        var artifactURLsByID: [String: URL] = [:]
        for artifact in manifest.artifacts {
            artifactURLsByID[artifact.id] = try Self.validatedArtifactURL(
                rootURL: rootURL,
                relativePath: artifact.relativePath
            )
        }
        guard let tokenizerURL = artifactURLsByID[contract.tokenizerArtifact.id] else {
            throw ChatterboxCoreAIError.bundledResourcesMissing
        }

        self.rootURL = rootURL
        self.contract = contract
        self.tokenizerURL = tokenizerURL
        self.artifactURLsByID = artifactURLsByID
    }

    func modelURL(for stage: ChatterboxPipelineStage) throws -> URL {
        let artifact = try contract.resolvedStage(stage).artifact
        guard let url = artifactURLsByID[artifact.id] else {
            throw ChatterboxCoreAIError.bundledResourcesMissing
        }
        return url
    }

    private static func validatedArtifactURL(
        rootURL: URL,
        relativePath: String
    ) throws -> URL {
        let candidate = rootURL.appending(path: relativePath).standardizedFileURL
        guard isDescendant(candidate, of: rootURL) else {
            throw ChatterboxCoreAIError.unsafeResourcePath(relativePath)
        }

        var currentURL = rootURL
        let rootComponentCount = rootURL.pathComponents.count
        for component in candidate.pathComponents.dropFirst(rootComponentCount) {
            currentURL.append(path: component)
            guard FileManager.default.fileExists(atPath: currentURL.path) else {
                throw ChatterboxCoreAIError.bundledResourcesMissing
            }
            let values = try currentURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw ChatterboxCoreAIError.unsafeResourcePath(relativePath)
            }
        }

        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard isDescendant(resolvedCandidate, of: resolvedRoot) else {
            throw ChatterboxCoreAIError.unsafeResourcePath(relativePath)
        }
        try rejectDescendantSymlinks(
            in: candidate,
            relativePath: relativePath
        )
        return resolvedCandidate
    }

    private static func rejectDescendantSymlinks(
        in artifactURL: URL,
        relativePath: String
    ) throws {
        let resourceValues = try artifactURL.resourceValues(
            forKeys: [.isDirectoryKey]
        )
        guard resourceValues.isDirectory == true else { return }

        var enumerationError: Error?
        let enumerator = FileManager.default.enumerator(
            at: artifactURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        )
        guard let enumerator else {
            throw ChatterboxCoreAIError.bundledResourcesMissing
        }
        for case let descendantURL as URL in enumerator {
            let values = try descendantURL.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            )
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                throw ChatterboxCoreAIError.unsafeResourcePath(relativePath)
            }
        }
        if let enumerationError {
            throw enumerationError
        }
    }

    private static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
    }
}
