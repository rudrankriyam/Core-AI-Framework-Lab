enum CoreAIPipelineNodeKind: String, Codable, CaseIterable, Sendable {
    case input
    case assetFunction
    case hostOperator
    case state
    case seededRandom
    case boundedLoop
    case output

    var title: String {
        switch self {
        case .input:
            "Input"
        case .assetFunction:
            "Asset function"
        case .hostOperator:
            "Host operator"
        case .state:
            "State"
        case .seededRandom:
            "Seeded random"
        case .boundedLoop:
            "Bounded loop"
        case .output:
            "Output"
        }
    }
}
