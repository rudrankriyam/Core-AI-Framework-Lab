struct CoreAIRecipeValidationIssue: Codable, Hashable, Identifiable, Sendable {
    enum Code: String, Codable, Sendable {
        case unsupportedSchemaVersion
        case invalidIdentifier
        case missingValue
        case duplicateValue
        case invalidExampleInput
        case invalidDynamicDimension
        case unknownReference
        case invalidState
        case invalidExternalization
        case invalidEntrypoint
        case incompleteAttribution
        case invalidPipeline
    }

    var code: Code
    var location: String
    var message: String

    var id: String {
        "\(code.rawValue):\(location):\(message)"
    }
}
