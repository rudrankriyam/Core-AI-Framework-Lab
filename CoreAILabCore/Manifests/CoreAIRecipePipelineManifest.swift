import Foundation

enum CoreAIExperienceKind: String, Codable, CaseIterable, Sendable {
    case audio
    case diffusion
    case embeddings
    case generic
    case textGeneration
    case textToSpeech
    case vision
}

struct CoreAIRecipePipelineStageManifest: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: String
    let displayName: String
    let detail: String
    let artifactID: String
    let entrypoints: [String: String]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String,
        displayName: String,
        detail: String,
        artifactID: String,
        entrypoints: [String: String]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.detail = detail
        self.artifactID = artifactID
        self.entrypoints = entrypoints
    }

    func validate(
        artifactsByID: [String: CoreAIArtifactManifest],
        path: String
    ) throws {
        try CoreAIManifestValidator.requireCurrentSchemaVersion(
            schemaVersion,
            supported: Self.currentSchemaVersion,
            path: "\(path).schemaVersion"
        )
        try CoreAIManifestValidator.requireNonempty(id, path: "\(path).id")
        try CoreAIManifestValidator.requireNonempty(
            displayName,
            path: "\(path).displayName"
        )
        try CoreAIManifestValidator.requireNonempty(detail, path: "\(path).detail")
        guard let artifact = artifactsByID[artifactID] else {
            throw CoreAIManifestValidationError.unknownReference(
                path: "\(path).artifactID",
                identifier: artifactID
            )
        }
        guard artifact.kind == .modelAsset else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "\(path).artifactID",
                reason: "pipeline stages must reference a model asset"
            )
        }
        guard !entrypoints.isEmpty else {
            throw CoreAIManifestValidationError.missingValue(
                path: "\(path).entrypoints"
            )
        }
        let requiredEntrypoints = Set(artifact.requiredEntrypoints)
        for (role, entrypoint) in entrypoints {
            try CoreAIManifestValidator.requireNonempty(
                role,
                path: "\(path).entrypoints.role"
            )
            try CoreAIManifestValidator.requireNonempty(
                entrypoint,
                path: "\(path).entrypoints.\(role)"
            )
            guard requiredEntrypoints.contains(entrypoint) else {
                throw CoreAIManifestValidationError.unknownReference(
                    path: "\(path).entrypoints.\(role)",
                    identifier: entrypoint
                )
            }
        }
        guard Set(entrypoints.values) == requiredEntrypoints else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "\(path).entrypoints",
                reason: "the stage must map every required artifact entrypoint"
            )
        }
    }
}

struct CoreAIRecipePipelineManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let experience: CoreAIExperienceKind
    let tokenizerArtifactID: String?
    let stages: [CoreAIRecipePipelineStageManifest]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        experience: CoreAIExperienceKind,
        tokenizerArtifactID: String? = nil,
        stages: [CoreAIRecipePipelineStageManifest]
    ) {
        self.schemaVersion = schemaVersion
        self.experience = experience
        self.tokenizerArtifactID = tokenizerArtifactID
        self.stages = stages
    }

    func validate(
        artifactsByID: [String: CoreAIArtifactManifest],
        path: String = "pipeline"
    ) throws {
        try CoreAIManifestValidator.requireCurrentSchemaVersion(
            schemaVersion,
            supported: Self.currentSchemaVersion,
            path: "\(path).schemaVersion"
        )
        guard !stages.isEmpty else {
            throw CoreAIManifestValidationError.missingValue(path: "\(path).stages")
        }
        try CoreAIManifestValidator.requireUniqueIdentifiers(
            stages,
            path: "\(path).stages",
            identifier: \.id
        )
        if let tokenizerArtifactID {
            guard let tokenizer = artifactsByID[tokenizerArtifactID] else {
                throw CoreAIManifestValidationError.unknownReference(
                    path: "\(path).tokenizerArtifactID",
                    identifier: tokenizerArtifactID
                )
            }
            guard tokenizer.kind == .tokenizer else {
                throw CoreAIManifestValidationError.invalidValue(
                    path: "\(path).tokenizerArtifactID",
                    reason: "the referenced artifact is not a tokenizer"
                )
            }
        }
        for (index, stage) in stages.enumerated() {
            try stage.validate(
                artifactsByID: artifactsByID,
                path: "\(path).stages[\(index)]"
            )
        }
    }
}
