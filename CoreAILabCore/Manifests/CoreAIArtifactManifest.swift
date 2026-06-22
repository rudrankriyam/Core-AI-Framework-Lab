import Foundation

enum CoreAIRecipeArtifactKind: String, Codable, CaseIterable, Sendable {
    case modelAsset
    case resourceBundle
    case tokenizer
    case auxiliaryFile
}

struct CoreAIArtifactManifest: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: String
    let displayName: String
    let kind: CoreAIRecipeArtifactKind
    let relativePath: String
    let precision: String?
    let requiredEntrypoints: [String]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String,
        displayName: String,
        kind: CoreAIRecipeArtifactKind,
        relativePath: String,
        precision: String? = nil,
        requiredEntrypoints: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.relativePath = relativePath
        self.precision = precision
        self.requiredEntrypoints = requiredEntrypoints
    }

    func validate(path: String = "artifact") throws {
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
        try CoreAIManifestValidator.requireSafeRelativePath(
            relativePath,
            path: "\(path).relativePath"
        )
        try CoreAIManifestValidator.requireUniqueIdentifiers(
            requiredEntrypoints,
            path: "\(path).requiredEntrypoints",
            identifier: { $0 }
        )
        for (index, entrypoint) in requiredEntrypoints.enumerated() {
            try CoreAIManifestValidator.requireNonempty(
                entrypoint,
                path: "\(path).requiredEntrypoints[\(index)]"
            )
        }
        if kind != .modelAsset && !requiredEntrypoints.isEmpty {
            throw CoreAIManifestValidationError.invalidValue(
                path: "\(path).requiredEntrypoints",
                reason: "only model assets can declare Core AI entrypoints"
            )
        }
    }
}
