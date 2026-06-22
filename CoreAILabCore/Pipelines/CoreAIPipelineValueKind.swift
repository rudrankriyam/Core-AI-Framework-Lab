enum CoreAIPipelineValueKind: String, Codable, CaseIterable, Sendable {
    case tensor
    case image
    case text
    case audio
    case tokens
    case scalar
    case opaque
}
