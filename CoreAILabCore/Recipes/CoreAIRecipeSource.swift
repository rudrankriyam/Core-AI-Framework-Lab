struct CoreAIRecipeSource: Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case localWorkspace
        case huggingFaceRepository

        var title: String {
            switch self {
            case .localWorkspace:
                "Local workspace"
            case .huggingFaceRepository:
                "Hugging Face repository"
            }
        }
    }

    var kind: Kind
    var location: String
    var revision: String
}
