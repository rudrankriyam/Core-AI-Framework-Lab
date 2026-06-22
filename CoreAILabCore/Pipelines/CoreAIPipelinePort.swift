struct CoreAIPipelinePort: Codable, Hashable, Identifiable, Sendable {
    let name: String
    let value: CoreAIPipelineValueContract
    let isOptional: Bool

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
