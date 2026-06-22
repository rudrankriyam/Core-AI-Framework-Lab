struct CoreAIRecipeModule: Codable, Hashable, Sendable {
    var modulePath: String
    var typeName: String
    var factoryFunction: String
    var checkpointPath: String
}
