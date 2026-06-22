import Foundation

struct CoreAIRecipeSourceManifest: Codable, Equatable, Sendable {
    let repository: String
    let revision: String
    let license: String

    func validate(path: String = "source") throws {
        try CoreAIManifestValidator.requireNonempty(
            repository,
            path: "\(path).repository"
        )
        try CoreAIManifestValidator.requireNonempty(
            revision,
            path: "\(path).revision"
        )
        try CoreAIManifestValidator.requireNonempty(license, path: "\(path).license")
    }
}

struct CoreAIRecipeManifest: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: String
    let revision: String
    let displayName: String
    let summary: String
    let systemImage: String
    let source: CoreAIRecipeSourceManifest
    let defaultTargetID: String
    let targets: [CoreAITargetManifest]
    let artifacts: [CoreAIArtifactManifest]
    let pipeline: CoreAIRecipePipelineManifest
    let capacity: CoreAICapacityManifest

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String,
        revision: String,
        displayName: String,
        summary: String,
        systemImage: String,
        source: CoreAIRecipeSourceManifest,
        defaultTargetID: String,
        targets: [CoreAITargetManifest],
        artifacts: [CoreAIArtifactManifest],
        pipeline: CoreAIRecipePipelineManifest,
        capacity: CoreAICapacityManifest
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.revision = revision
        self.displayName = displayName
        self.summary = summary
        self.systemImage = systemImage
        self.source = source
        self.defaultTargetID = defaultTargetID
        self.targets = targets
        self.artifacts = artifacts
        self.pipeline = pipeline
        self.capacity = capacity
    }

    var defaultTarget: CoreAITargetManifest? {
        targets.first { $0.id == defaultTargetID }
    }

    func artifact(id: String) -> CoreAIArtifactManifest? {
        artifacts.first { $0.id == id }
    }

    func validate() throws {
        try CoreAIManifestValidator.requireCurrentSchemaVersion(
            schemaVersion,
            supported: Self.currentSchemaVersion,
            path: "recipe.schemaVersion"
        )
        try CoreAIManifestValidator.requireNonempty(id, path: "recipe.id")
        try CoreAIManifestValidator.requireNonempty(revision, path: "recipe.revision")
        try CoreAIManifestValidator.requireNonempty(
            displayName,
            path: "recipe.displayName"
        )
        try CoreAIManifestValidator.requireNonempty(summary, path: "recipe.summary")
        try CoreAIManifestValidator.requireNonempty(
            systemImage,
            path: "recipe.systemImage"
        )
        try source.validate()
        guard !targets.isEmpty else {
            throw CoreAIManifestValidationError.missingValue(path: "recipe.targets")
        }
        try CoreAIManifestValidator.requireUniqueIdentifiers(
            targets,
            path: "recipe.targets",
            identifier: \.id
        )
        for (index, target) in targets.enumerated() {
            try target.validate(path: "recipe.targets[\(index)]")
        }
        guard defaultTarget != nil else {
            throw CoreAIManifestValidationError.unknownReference(
                path: "recipe.defaultTargetID",
                identifier: defaultTargetID
            )
        }

        guard !artifacts.isEmpty else {
            throw CoreAIManifestValidationError.missingValue(path: "recipe.artifacts")
        }
        try CoreAIManifestValidator.requireUniqueIdentifiers(
            artifacts,
            path: "recipe.artifacts",
            identifier: \.id
        )
        try CoreAIManifestValidator.requireUniqueIdentifiers(
            artifacts,
            path: "recipe.artifacts.relativePath",
            identifier: \.relativePath
        )
        for (index, artifact) in artifacts.enumerated() {
            try artifact.validate(path: "recipe.artifacts[\(index)]")
        }
        let artifactsByID = Dictionary(
            uniqueKeysWithValues: artifacts.map { ($0.id, $0) }
        )
        try pipeline.validate(artifactsByID: artifactsByID)
        try capacity.validate()
    }
}
