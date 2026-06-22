struct CoreAIRecipeFunctionEntrypoint: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var moduleMethod: String
    var inputNames: [String]
    var outputNames: [String]
    var stateNames: [String]
}
