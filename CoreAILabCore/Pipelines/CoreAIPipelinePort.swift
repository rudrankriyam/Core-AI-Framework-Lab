struct CoreAIPipelinePort: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var value: CoreAIPipelineValueContract
    var isOptional: Bool

    var id: String { name }

    init(
        name: String,
        value: CoreAIPipelineValueContract,
        isOptional: Bool = false
    ) {
        self.name = name
        self.value = value
        self.isOptional = isOptional
    }
}
