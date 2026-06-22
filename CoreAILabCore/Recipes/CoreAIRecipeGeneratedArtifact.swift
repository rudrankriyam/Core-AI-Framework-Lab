struct CoreAIRecipeGeneratedArtifact: Hashable, Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case customLowering
        case metalKernel

        var title: String {
            switch self {
            case .customLowering:
                "Custom lowering"
            case .metalKernel:
                "Metal kernel"
            }
        }
    }

    var relativePath: String
    var kind: Kind
    var contents: String

    var id: String { relativePath }
}
