import CoreAI
import Foundation

struct CoreAIModelAssetReport: Sendable, Equatable {
    let url: URL
    let isValid: Bool
    let author: String
    let license: String
    let description: String
    let functions: [CoreAIAssetFunctionSignature]
    let storageTypes: [CoreAIAssetStorageTypeSummary]
    let computeTypes: [String]
    let operationDistribution: [CoreAIAssetOperationCount]

    var functionNames: [String] {
        functions.map(\.name)
    }

    init(
        url: URL,
        isValid: Bool,
        author: String,
        license: String,
        description: String,
        functions: [CoreAIAssetFunctionSignature],
        storageTypes: [CoreAIAssetStorageTypeSummary] = [],
        computeTypes: [String],
        operationDistribution: [CoreAIAssetOperationCount] = []
    ) {
        self.url = url
        self.isValid = isValid
        self.author = author
        self.license = license
        self.description = description
        self.functions = functions
        self.storageTypes = storageTypes
        self.computeTypes = computeTypes
        self.operationDistribution = operationDistribution
    }

    init(
        url: URL,
        isValid: Bool,
        author: String,
        license: String,
        description: String,
        functionNames: [String],
        computeTypes: [String]
    ) {
        self.init(
            url: url,
            isValid: isValid,
            author: author,
            license: license,
            description: description,
            functions: functionNames.map {
                CoreAIAssetFunctionSignature(
                    name: $0,
                    inputs: [],
                    states: [],
                    outputs: []
                )
            },
            computeTypes: computeTypes
        )
    }
}

enum CoreAIModelAssetInspector {
    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func inspect(url: URL, includingStatistics: Bool = false) throws -> CoreAIModelAssetReport {
        let isValid = AIModelAsset.isValid(at: url)
        let asset = try AIModelAsset(contentsOf: url)
        let summary = try asset.summary(includingStatistics: includingStatistics)

        return CoreAIModelAssetReport(
            url: url,
            isValid: isValid,
            author: asset.metadata.author,
            license: asset.metadata.license,
            description: asset.metadata.description,
            functions: summary?.functions.map { function in
                CoreAIAssetFunctionSignature(
                    name: function.name,
                    inputs: function.inputs.map(signature),
                    states: function.states.map(signature),
                    outputs: function.outputs.map(signature)
                )
            } ?? [],
            storageTypes: summary?.storageTypes.map {
                CoreAIAssetStorageTypeSummary(
                    typeName: $0.typeName,
                    count: $0.count
                )
            }.sorted { $0.typeName < $1.typeName } ?? [],
            computeTypes: summary?.computeTypes ?? [],
            operationDistribution: summary?.operationDistribution.map {
                CoreAIAssetOperationCount(
                    operationName: $0.operationName,
                    count: $0.count
                )
            }.sorted { $0.operationName < $1.operationName } ?? []
        )
    }

    private static func signature(
        _ descriptor: AIModelAsset.ValueDescriptor
    ) -> CoreAIAssetValueSignature {
        CoreAIAssetValueSignature(
            name: descriptor.name,
            typeName: descriptor.typeName
        )
    }
}
