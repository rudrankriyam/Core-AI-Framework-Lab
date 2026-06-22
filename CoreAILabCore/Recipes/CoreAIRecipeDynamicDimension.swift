struct CoreAIRecipeDynamicDimension: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var inputName: String
    var axis: Int
    var symbol: String
    var minimum: Int
    var maximum: Int
}
