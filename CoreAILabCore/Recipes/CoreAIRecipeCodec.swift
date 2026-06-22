import Foundation

enum CoreAIRecipeCodec {
    private struct SchemaHeader: Decodable {
        var schemaVersion: Int
    }

    static func encode(_ recipe: CoreAIRecipeManifest) throws -> Data {
        try CoreAIRecipeValidator.validate(recipe)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(recipe)
    }

    static func decode(_ data: Data) throws -> CoreAIRecipeManifest {
        let decoder = JSONDecoder()
        let header = try decoder.decode(SchemaHeader.self, from: data)
        guard header.schemaVersion == CoreAIRecipeManifest.currentSchemaVersion else {
            throw CoreAIRecipeValidationError(issues: [
                CoreAIRecipeValidationIssue(
                    code: .unsupportedSchemaVersion,
                    location: "schemaVersion",
                    message: "Recipe schema version \(header.schemaVersion) is unsupported."
                )
            ])
        }
        let recipe = try decoder.decode(CoreAIRecipeManifest.self, from: data)
        try CoreAIRecipeValidator.validate(recipe)
        return recipe
    }
}
