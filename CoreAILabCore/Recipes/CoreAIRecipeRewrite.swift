struct CoreAIRecipeRewrite: Codable, Hashable, Identifiable, Sendable {
    enum Strategy: String, Codable, CaseIterable, Sendable {
        case sourceRewrite
        case decomposition
        case customLowering
        case metalKernel

        var title: String {
            switch self {
            case .sourceRewrite:
                "Source rewrite"
            case .decomposition:
                "Decomposition"
            case .customLowering:
                "Custom lowering"
            case .metalKernel:
                "Metal kernel"
            }
        }
    }

    var id: String
    var title: String
    var operatorNames: [String]
    var strategy: Strategy
    var summary: String
    var evidence: String
}
