enum CoreAIPipelineValueKind: String, Codable, CaseIterable, Sendable {
    case tensor
    case image
    case text
    case audio
    case tokens
    case scalar
    case opaque

    var title: String {
        switch self {
        case .tensor:
            "Tensor"
        case .image:
            "Image"
        case .text:
            "Text"
        case .audio:
            "Audio"
        case .tokens:
            "Tokens"
        case .scalar:
            "Scalar"
        case .opaque:
            "Opaque"
        }
    }
}
