struct CoreAIRecipeManifest: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: String
    var displayName: String
    var source: CoreAIRecipeSource
    var module: CoreAIRecipeModule
    var exampleInputs: [CoreAIRecipeExampleInput]
    var dynamicDimensions: [CoreAIRecipeDynamicDimension]
    var stateBindings: [CoreAIRecipeStateBinding]
    var externalizationRules: [CoreAIRecipeExternalizationRule]
    var functionEntrypoints: [CoreAIRecipeFunctionEntrypoint]
    var unsupportedOperations: [CoreAIUnsupportedOperationFinding]
    var pipeline: CoreAIPipelineManifest

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String,
        displayName: String,
        source: CoreAIRecipeSource,
        module: CoreAIRecipeModule,
        exampleInputs: [CoreAIRecipeExampleInput],
        dynamicDimensions: [CoreAIRecipeDynamicDimension],
        stateBindings: [CoreAIRecipeStateBinding],
        externalizationRules: [CoreAIRecipeExternalizationRule],
        functionEntrypoints: [CoreAIRecipeFunctionEntrypoint],
        unsupportedOperations: [CoreAIUnsupportedOperationFinding],
        pipeline: CoreAIPipelineManifest
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.source = source
        self.module = module
        self.exampleInputs = exampleInputs
        self.dynamicDimensions = dynamicDimensions
        self.stateBindings = stateBindings
        self.externalizationRules = externalizationRules
        self.functionEntrypoints = functionEntrypoints
        self.unsupportedOperations = unsupportedOperations
        self.pipeline = pipeline
    }

    static var starter: Self {
        let value = CoreAIPipelineValueContract(
            kind: .tensor,
            scalarType: "float32",
            shape: [
                .fixed(1),
                .fixed(80),
                .dynamic("sequence", minimum: 32, maximum: 3_000)
            ],
            semantic: "features"
        )
        let input = CoreAIPipelineNode(
            id: "features_input",
            kind: .input,
            title: "Features",
            outputs: [CoreAIPipelinePort(name: "features", value: value)]
        )
        let function = CoreAIPipelineNode(
            id: "model_forward",
            kind: .assetFunction,
            title: "Model forward",
            reference: "main.forward",
            inputs: [CoreAIPipelinePort(name: "features", value: value)],
            outputs: [CoreAIPipelinePort(name: "output", value: value)]
        )
        let output = CoreAIPipelineNode(
            id: "model_output",
            kind: .output,
            title: "Output",
            inputs: [CoreAIPipelinePort(name: "output", value: value)]
        )

        return Self(
            id: "untitled_recipe",
            displayName: "Untitled Experimental Recipe",
            source: CoreAIRecipeSource(
                kind: .localWorkspace,
                location: "model.py",
                revision: ""
            ),
            module: CoreAIRecipeModule(
                modulePath: "model",
                typeName: "Model",
                factoryFunction: "",
                checkpointPath: ""
            ),
            exampleInputs: [
                CoreAIRecipeExampleInput(
                    id: "features",
                    name: "features",
                    kind: .tensor,
                    scalarType: "float32",
                    shape: [1, 80, 300],
                    fixturePath: "",
                    literalValue: ""
                )
            ],
            dynamicDimensions: [
                CoreAIRecipeDynamicDimension(
                    id: "features_sequence",
                    inputName: "features",
                    axis: 2,
                    symbol: "sequence",
                    minimum: 32,
                    maximum: 3_000
                )
            ],
            stateBindings: [],
            externalizationRules: [],
            functionEntrypoints: [
                CoreAIRecipeFunctionEntrypoint(
                    id: "forward",
                    name: "forward",
                    moduleMethod: "forward",
                    inputNames: ["features"],
                    outputNames: ["output"],
                    stateNames: []
                )
            ],
            unsupportedOperations: [],
            pipeline: CoreAIPipelineManifest(
                id: "untitled_pipeline",
                displayName: "Untitled Pipeline",
                hostOperatorRegistryVersion: 1,
                nodes: [input, function, output],
                edges: [
                    CoreAIPipelineEdge(
                        source: CoreAIPipelineEndpoint(
                            nodeID: input.id,
                            portName: "features"
                        ),
                        destination: CoreAIPipelineEndpoint(
                            nodeID: function.id,
                            portName: "features"
                        )
                    ),
                    CoreAIPipelineEdge(
                        source: CoreAIPipelineEndpoint(
                            nodeID: function.id,
                            portName: "output"
                        ),
                        destination: CoreAIPipelineEndpoint(
                            nodeID: output.id,
                            portName: "output"
                        )
                    )
                ]
            )
        )
    }
}
