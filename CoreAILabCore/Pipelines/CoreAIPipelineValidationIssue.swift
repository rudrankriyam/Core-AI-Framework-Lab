struct CoreAIPipelineValidationIssue: Codable, Hashable, Identifiable, Sendable {
    let code: CoreAIPipelineValidationCode
    let location: String
    let message: String

    var id: String {
        "\(code.rawValue):\(location):\(message)"
    }
}
