struct CoreAIRecipeExternalizationRule: Codable, Hashable, Identifiable, Sendable {
    enum Strategy: String, Codable, CaseIterable, Sendable {
        case automatic
        case separateWeights
        case sharedResource

        var title: String {
            switch self {
            case .automatic:
                "Automatic"
            case .separateWeights:
                "Separate weights"
            case .sharedResource:
                "Shared resource"
            }
        }
    }

    var id: String
    var modulePath: String
    var strategy: Strategy
    var minimumBytes: Int
    var resourceName: String
}
