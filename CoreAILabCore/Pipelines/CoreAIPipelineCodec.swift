import Foundation

enum CoreAIPipelineCodec {
    private struct SchemaHeader: Decodable {
        let schemaVersion: Int
    }

    static func encode(_ manifest: CoreAIPipelineManifest) throws -> Data {
        try CoreAIPipelineValidator.validate(manifest)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    static func decode(_ data: Data) throws -> CoreAIPipelineManifest {
        let decoder = JSONDecoder()
        let header = try decoder.decode(SchemaHeader.self, from: data)
        guard header.schemaVersion == CoreAIPipelineManifest.currentSchemaVersion else {
            throw CoreAIPipelineValidationError(issues: [
                CoreAIPipelineValidationIssue(
                    code: .unsupportedSchemaVersion,
                    location: "schemaVersion",
                    message: "Pipeline schema version \(header.schemaVersion) is unsupported."
                )
            ])
        }
        let manifest = try decoder.decode(CoreAIPipelineManifest.self, from: data)
        try CoreAIPipelineValidator.validate(manifest)
        return manifest
    }
}
