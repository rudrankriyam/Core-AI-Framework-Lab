struct CoreAIRecipeStateBinding: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var inputName: String
    var outputName: String
    var initialValueReference: String
    var isMutable: Bool

}
