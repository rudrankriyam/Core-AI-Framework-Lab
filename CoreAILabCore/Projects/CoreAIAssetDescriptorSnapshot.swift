import Foundation

struct CoreAIAssetDescriptorSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let isValid: Bool
    let author: String
    let license: String
    let assetDescription: String
    let functions: [CoreAIAssetFunctionSignature]
    let storageTypes: [CoreAIAssetStorageTypeSummary]
    let computeTypes: [String]
    let operationDistribution: [CoreAIAssetOperationCount]

    init(report: CoreAIModelAssetReport) {
        schemaVersion = Self.currentSchemaVersion
        isValid = report.isValid
        author = report.author
        license = report.license
        assetDescription = report.description
        functions = report.functions
            .map { function in
                CoreAIAssetFunctionSignature(
                    name: function.name,
                    inputs: function.inputs.sorted { $0.name < $1.name },
                    states: function.states.sorted { $0.name < $1.name },
                    outputs: function.outputs.sorted { $0.name < $1.name }
                )
            }
            .sorted { $0.name < $1.name }
        storageTypes = report.storageTypes.sorted { $0.typeName < $1.typeName }
        computeTypes = Array(Set(report.computeTypes)).sorted()
        operationDistribution = report.operationDistribution.sorted {
            $0.operationName < $1.operationName
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        isValid = try container.decode(Bool.self, forKey: .isValid)
        author = try container.decode(String.self, forKey: .author)
        license = try container.decode(String.self, forKey: .license)
        assetDescription = try container.decode(String.self, forKey: .assetDescription)
        functions = try container.decode(
            [CoreAIAssetFunctionSignature].self,
            forKey: .functions
        )
        storageTypes = try container.decodeIfPresent(
            [CoreAIAssetStorageTypeSummary].self,
            forKey: .storageTypes
        ) ?? []
        computeTypes = try container.decode([String].self, forKey: .computeTypes)
        operationDistribution = try container.decodeIfPresent(
            [CoreAIAssetOperationCount].self,
            forKey: .operationDistribution
        ) ?? []
    }

    func validate() throws {
        try CoreAIManifestValidator.requireCurrentSchemaVersion(
            schemaVersion,
            supported: Self.currentSchemaVersion,
            path: "descriptorSnapshot.schemaVersion"
        )
        try CoreAIManifestValidator.requireUniqueIdentifiers(
            functions,
            path: "descriptorSnapshot.functions",
            identifier: \CoreAIAssetFunctionSignature.name
        )
        try validateStorageTypes()
        try validateOperationDistribution()
        guard functions == functions.sorted(by: { $0.name < $1.name }),
              computeTypes == Array(Set(computeTypes)).sorted()
        else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "descriptorSnapshot",
                reason: "functions and compute types must use deterministic ordering"
            )
        }
        for (functionIndex, function) in functions.enumerated() {
            try CoreAIManifestValidator.requireNonempty(
                function.name,
                path: "descriptorSnapshot.functions[\(functionIndex)].name"
            )
            try validate(
                function.inputs,
                path: "descriptorSnapshot.functions[\(functionIndex)].inputs"
            )
            try validate(
                function.states,
                path: "descriptorSnapshot.functions[\(functionIndex)].states"
            )
            try validate(
                function.outputs,
                path: "descriptorSnapshot.functions[\(functionIndex)].outputs"
            )
        }
    }

    private func validateStorageTypes() throws {
        try CoreAIManifestValidator.requireUniqueIdentifiers(
            storageTypes,
            path: "descriptorSnapshot.storageTypes",
            identifier: \CoreAIAssetStorageTypeSummary.typeName
        )
        guard storageTypes == storageTypes.sorted(by: { $0.typeName < $1.typeName }) else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "descriptorSnapshot.storageTypes",
                reason: "storage types must use deterministic ordering"
            )
        }
        for (index, storageType) in storageTypes.enumerated() {
            try CoreAIManifestValidator.requireNonempty(
                storageType.typeName,
                path: "descriptorSnapshot.storageTypes[\(index)].typeName"
            )
            guard storageType.count >= 0 else {
                throw CoreAIManifestValidationError.invalidValue(
                    path: "descriptorSnapshot.storageTypes[\(index)].count",
                    reason: "must not be negative"
                )
            }
        }
    }

    private func validateOperationDistribution() throws {
        try CoreAIManifestValidator.requireUniqueIdentifiers(
            operationDistribution,
            path: "descriptorSnapshot.operationDistribution",
            identifier: \CoreAIAssetOperationCount.operationName
        )
        guard operationDistribution == operationDistribution.sorted(by: {
            $0.operationName < $1.operationName
        }) else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "descriptorSnapshot.operationDistribution",
                reason: "operations must use deterministic ordering"
            )
        }
        for (index, operation) in operationDistribution.enumerated() {
            try CoreAIManifestValidator.requireNonempty(
                operation.operationName,
                path: "descriptorSnapshot.operationDistribution[\(index)].operationName"
            )
            guard operation.count >= 0 else {
                throw CoreAIManifestValidationError.invalidValue(
                    path: "descriptorSnapshot.operationDistribution[\(index)].count",
                    reason: "must not be negative"
                )
            }
        }
    }

    private func validate(
        _ values: [CoreAIAssetValueSignature],
        path: String
    ) throws {
        try CoreAIManifestValidator.requireUniqueIdentifiers(
            values,
            path: path,
            identifier: \CoreAIAssetValueSignature.name
        )
        guard values == values.sorted(by: { $0.name < $1.name }) else {
            throw CoreAIManifestValidationError.invalidValue(
                path: path,
                reason: "values must use deterministic ordering"
            )
        }
        for (index, value) in values.enumerated() {
            try CoreAIManifestValidator.requireNonempty(
                value.name,
                path: "\(path)[\(index)].name"
            )
            try CoreAIManifestValidator.requireNonempty(
                value.typeName,
                path: "\(path)[\(index)].typeName"
            )
        }
    }
}
