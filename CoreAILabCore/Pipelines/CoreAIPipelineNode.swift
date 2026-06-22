struct CoreAIPipelineNode: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let kind: CoreAIPipelineNodeKind
    let title: String
    let reference: String?
    let inputs: [CoreAIPipelinePort]
    let outputs: [CoreAIPipelinePort]
    let stateKey: String?
    let ownerNodeID: String?
    let fixedSeed: UInt64?
    let seedInputPort: String?
    let maximumIterations: Int?
    let stopConditionInputPort: String?

    init(
        id: String,
        kind: CoreAIPipelineNodeKind,
        title: String,
        reference: String? = nil,
        inputs: [CoreAIPipelinePort] = [],
        outputs: [CoreAIPipelinePort] = [],
        stateKey: String? = nil,
        ownerNodeID: String? = nil,
        fixedSeed: UInt64? = nil,
        seedInputPort: String? = nil,
        maximumIterations: Int? = nil,
        stopConditionInputPort: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.reference = reference
        self.inputs = inputs
        self.outputs = outputs
        self.stateKey = stateKey
        self.ownerNodeID = ownerNodeID
        self.fixedSeed = fixedSeed
        self.seedInputPort = seedInputPort
        self.maximumIterations = maximumIterations
        self.stopConditionInputPort = stopConditionInputPort
    }
}
