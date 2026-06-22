struct CoreAIRecipeExampleInput: Codable, Hashable, Identifiable, Sendable {
    enum ValueKind: String, Codable, CaseIterable, Sendable {
        case tensor
        case scalar
        case boolean
        case text

        var title: String {
            switch self {
            case .tensor:
                "Tensor"
            case .scalar:
                "Scalar"
            case .boolean:
                "Boolean"
            case .text:
                "Text"
            }
        }
    }

    var id: String
    var name: String
    var kind: ValueKind
    var scalarType: String
    var shape: [Int]
    var fixturePath: String
    var literalValue: String
}
