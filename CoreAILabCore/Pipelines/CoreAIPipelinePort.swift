struct CoreAIPipelinePort: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var value: CoreAIPipelineValueContract
    var isOptional = false

    var id: String { name }
}
