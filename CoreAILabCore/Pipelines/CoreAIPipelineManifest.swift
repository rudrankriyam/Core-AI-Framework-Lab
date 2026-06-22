struct CoreAIPipelineManifest: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var id: String
    var displayName: String
    var hostOperatorRegistryVersion: Int
    var nodes: [CoreAIPipelineNode]
    var edges: [CoreAIPipelineEdge]
}
