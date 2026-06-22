struct CoreAIPipelineNode: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var kind: CoreAIPipelineNodeKind
    var title: String
    var reference: String?
    var inputs: [CoreAIPipelinePort]
    var outputs: [CoreAIPipelinePort]
    var stateKey: String?
    var ownerNodeID: String?
    var fixedSeed: UInt64?
    var seedInputPort: String?
    var maximumIterations: Int?
    var stopConditionInputPort: String?

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

    mutating func applyConfigurationDefaults() {
        let previousSeedInputPort = seedInputPort
        let previousStopConditionInputPort = stopConditionInputPort
        let defaultValue = CoreAIPipelineValueContract(
            kind: .tensor,
            scalarType: "float32",
            shape: [.fixed(1)]
        )
        reference = [.assetFunction, .hostOperator].contains(kind)
            ? (reference ?? "executable.reference")
            : nil
        stateKey = kind == .state ? (stateKey ?? "state") : nil
        ownerNodeID = kind == .state ? ownerNodeID : nil
        if kind == .seededRandom {
            if seedInputPort == nil || fixedSeed != nil {
                fixedSeed = fixedSeed ?? 0
                seedInputPort = nil
            }
        } else {
            fixedSeed = nil
            seedInputPort = nil
        }
        maximumIterations = kind == .boundedLoop ? (maximumIterations ?? 1) : nil
        if kind == .boundedLoop {
            if stopConditionInputPort?.isEmpty ?? true {
                stopConditionInputPort = "stop"
            }
        } else {
            stopConditionInputPort = nil
        }

        if kind != .boundedLoop, let previousStopConditionInputPort {
            inputs.removeAll { $0.name == previousStopConditionInputPort }
        }
        if let previousSeedInputPort,
           kind != .seededRandom || seedInputPort == nil {
            inputs.removeAll { $0.name == previousSeedInputPort }
        }

        switch kind {
        case .input:
            inputs = []
            if outputs.isEmpty {
                outputs = [CoreAIPipelinePort(name: "output", value: defaultValue)]
            }
        case .output:
            outputs = []
            if inputs.isEmpty {
                inputs = [CoreAIPipelinePort(name: "input", value: defaultValue)]
            }
        case .assetFunction, .hostOperator:
            if inputs.isEmpty {
                inputs = [CoreAIPipelinePort(name: "input", value: defaultValue)]
            }
            if outputs.isEmpty {
                outputs = [CoreAIPipelinePort(name: "output", value: defaultValue)]
            }
        case .state:
            inputs = []
            outputs = []
        case .seededRandom:
            if seedInputPort == nil {
                inputs = []
            }
            if outputs.isEmpty {
                outputs = [CoreAIPipelinePort(name: "output", value: defaultValue)]
            }
        case .boundedLoop:
            let stopPortName = stopConditionInputPort ?? "stop"
            if !inputs.contains(where: { $0.name != stopPortName }) {
                inputs.append(CoreAIPipelinePort(name: "input", value: defaultValue))
            }
            if !inputs.contains(where: { $0.name == stopPortName }) {
                inputs.append(CoreAIPipelinePort(
                    name: stopPortName,
                    value: CoreAIPipelineValueContract(
                        kind: .scalar,
                        scalarType: "bool"
                    )
                ))
            }
            if outputs.isEmpty {
                outputs = [CoreAIPipelinePort(name: "output", value: defaultValue)]
            }
        }
    }
}
