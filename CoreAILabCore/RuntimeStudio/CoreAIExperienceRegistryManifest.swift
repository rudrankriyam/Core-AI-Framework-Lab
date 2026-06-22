import Foundation

struct CoreAIExperienceRegistryManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let mappings: [CoreAIRecipeExperienceMapping]
}
