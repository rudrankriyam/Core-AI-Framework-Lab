import Foundation
import SwiftData

@Model
final class CoreAIRecipeRevisionRecord {
    @Attribute(.unique) private(set) var id: UUID = UUID()
    private(set) var schemaVersion: Int = 1
    private(set) var recipeIdentifier: String = ""
    private(set) var recipeRevision: String = ""
    private(set) var displayName: String = ""
    private(set) var manifestData: Data = Data()
    private(set) var createdAt: Date = Date.now
    private(set) var project: LabProject?

    @Relationship(deleteRule: .nullify, inverse: \CoreAIRunRecord.recipeRevision)
    private(set) var runs: [CoreAIRunRecord] = []

    init(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        id: UUID = UUID(),
        schemaVersion: Int = 1,
        recipeIdentifier: String,
        recipeRevision: String,
        displayName: String,
        manifestData: Data,
        createdAt: Date = .now,
        project: LabProject? = nil,
        runs: [CoreAIRunRecord] = []
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.recipeIdentifier = recipeIdentifier
        self.recipeRevision = recipeRevision
        self.displayName = displayName
        self.manifestData = manifestData
        self.createdAt = createdAt
        self.project = project
        self.runs = runs
    }

    func decodedManifest() throws -> CoreAIRecipeManifest {
        let manifest = try JSONDecoder().decode(
            CoreAIRecipeManifest.self,
            from: manifestData
        )
        try manifest.validate()
        guard schemaVersion == 1,
              manifest.id == recipeIdentifier,
              manifest.revision == recipeRevision,
              manifest.displayName == displayName else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "recipeRevisionRecord",
                reason: "stored snapshot metadata does not match its manifest"
            )
        }
        return manifest
    }
}
