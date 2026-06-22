enum CoreAIPipelineNodeKind: String, Codable, CaseIterable, Sendable {
    case input
    case assetFunction
    case hostOperator
    case state
    case seededRandom
    case boundedLoop
    case output
}
