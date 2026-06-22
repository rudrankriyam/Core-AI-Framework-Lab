struct CoreAIPipelineManifest: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: String
    let displayName: String
    let hostOperatorRegistryVersion: Int
    let nodes: [CoreAIPipelineNode]
    let edges: [CoreAIPipelineEdge]

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
