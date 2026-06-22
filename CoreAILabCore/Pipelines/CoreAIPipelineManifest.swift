struct CoreAIPipelineManifest: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: String
    var displayName: String
    var hostOperatorRegistryVersion: Int
    var nodes: [CoreAIPipelineNode]
    var edges: [CoreAIPipelineEdge]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String,
        displayName: String,
        hostOperatorRegistryVersion: Int,
        nodes: [CoreAIPipelineNode],
        edges: [CoreAIPipelineEdge]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.hostOperatorRegistryVersion = hostOperatorRegistryVersion
        self.nodes = nodes
        self.edges = edges
    }
}
