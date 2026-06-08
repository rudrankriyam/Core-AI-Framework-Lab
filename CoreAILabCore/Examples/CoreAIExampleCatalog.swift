import Foundation

struct CoreAIExampleCatalog: Sendable {
    let examples: [CoreAIExample]

    static let current = CoreAIExampleCatalog(
        examples: [
            CoreAIExample(
                title: "Runtime Discovery",
                summary: "Read the current Core AI architecture and available compute units.",
                sourceFile: "CoreAIDiscoverySnapshot.swift"
            ),
            CoreAIExample(
                title: "Asset Inspection",
                summary: "Validate a model asset, read metadata, and summarize functions and compute types.",
                sourceFile: "CoreAIModelAssetInspector.swift"
            ),
            CoreAIExample(
                title: "Specialization",
                summary: "Create specialization options for CPU, GPU, or Neural Engine execution.",
                sourceFile: "CoreAIModelLoader.swift"
            ),
            CoreAIExample(
                title: "Cache Policy",
                summary: "Use the default cache, app-group caches, persistent policy, and purge conditions.",
                sourceFile: "CoreAIModelCacheExamples.swift"
            ),
            CoreAIExample(
                title: "Function Descriptors",
                summary: "Inspect function input, state, and output descriptors before running inference.",
                sourceFile: "CoreAIFunctionDescriptorExamples.swift"
            ),
            CoreAIExample(
                title: "Inference Scaffolding",
                summary: "Prepare the model/function/input flow that will become the first end-to-end sample.",
                sourceFile: "CoreAIInferenceExamples.swift"
            ),
            CoreAIExample(
                title: "Tensor and Image Descriptors",
                summary: "Read descriptor summaries for NDArray and image-shaped values.",
                sourceFile: "CoreAIValueDescriptorExamples.swift"
            )
        ]
    )
}

struct CoreAIExample: Identifiable, Sendable {
    var id: String { sourceFile }
    let title: String
    let summary: String
    let sourceFile: String
}
