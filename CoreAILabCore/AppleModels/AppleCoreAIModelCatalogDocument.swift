import Foundation

struct AppleCoreAIModelCatalogDocument: Codable, Sendable {
    let sourceRepository: String
    let sourceRevision: String
    let generatedAt: String
    let models: [AppleCoreAIModel]

    enum CodingKeys: String, CodingKey {
        case sourceRepository = "source_repository"
        case sourceRevision = "source_revision"
        case generatedAt = "generated_at"
        case models
    }
}
