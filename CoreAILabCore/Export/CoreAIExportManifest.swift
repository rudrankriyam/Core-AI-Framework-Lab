import Foundation

struct CoreAIExportManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let package: Package
    let artifact: Artifact
    let metadata: Metadata
    let specialization: Specialization
    let functions: [Function]

    init(
        package: Package,
        artifact: Artifact,
        report: CoreAIModelAssetReport,
        specializationConfiguration: CoreAISpecializationConfiguration,
        contracts: [CoreAIFunctionContract]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.package = package
        self.artifact = artifact
        metadata = Metadata(
            author: report.author,
            license: report.license,
            description: report.description,
            computeTypes: report.computeTypes.sorted()
        )
        specialization = Specialization(configuration: specializationConfiguration)
        functions = contracts.sorted { $0.name < $1.name }.map(Function.init)
    }

    struct Package: Codable, Equatable, Sendable {
        let name: String
        let productName: String
        let targetName: String
        let swiftToolsVersion: String
        let generatedSourceRelativePath: String
        let resourcesRelativePath: String
    }

    struct Artifact: Codable, Equatable, Sendable {
        let relativePath: String
        let sha256: String
        let byteCount: Int64
    }

    struct Metadata: Codable, Equatable, Sendable {
        let author: String
        let license: String
        let description: String
        let computeTypes: [String]
    }

    struct Specialization: Codable, Equatable, Sendable {
        let profile: String
        let preferredCompute: String?
        let expectFrequentReshapes: Bool
        let runtimeDefaultsToCPUOnly: Bool

        init(configuration: CoreAISpecializationConfiguration) {
            let profile = configuration.profile
            self.profile = profile.rawValue
            expectFrequentReshapes = configuration.expectFrequentReshapes
            runtimeDefaultsToCPUOnly = profile == .cpuOnly
            switch profile {
            case .preferGPU:
                preferredCompute = "gpu"
            case .preferNeuralEngine:
                preferredCompute = "neural-engine"
            case .automatic, .cpuOnly:
                preferredCompute = nil
            }
        }
    }

    struct Function: Codable, Equatable, Sendable {
        let name: String
        let inputs: [Value]
        let states: [Value]
        let outputs: [Value]
        let generatedRuntimeUnsupportedReason: String?

        init(contract: CoreAIFunctionContract) {
            name = contract.name
            inputs = contract.inputs.map(Value.init)
            states = contract.states.map(Value.init)
            outputs = contract.outputs.map(Value.init)
            generatedRuntimeUnsupportedReason = contract.generatedRuntimeUnsupportedReason
        }
    }

    struct Value: Codable, Equatable, Sendable {
        let name: String
        let kind: String
        let scalarType: String?
        let shape: [Int]?
        let hasDynamicShape: Bool?
        let minimumByteCount: Int?
        let width: Int?
        let height: Int?
        let pixelFormatType: UInt32?

        init(contract: CoreAIFunctionValueContract) {
            name = contract.name
            switch contract.kind {
            case .tensor(let tensor):
                kind = "ndArray"
                scalarType = tensor.scalarTypeName
                shape = tensor.shape
                hasDynamicShape = tensor.hasDynamicShape
                minimumByteCount = tensor.minimumByteCount
                width = nil
                height = nil
                pixelFormatType = nil
            case .image(let image):
                kind = "image"
                scalarType = nil
                shape = nil
                hasDynamicShape = nil
                minimumByteCount = nil
                width = image.width
                height = image.height
                pixelFormatType = image.pixelFormatType
            case .unknown:
                kind = "unknown"
                scalarType = nil
                shape = nil
                hasDynamicShape = nil
                minimumByteCount = nil
                width = nil
                height = nil
                pixelFormatType = nil
            }
        }
    }
}

extension CoreAIFunctionContract {
    var supportsGeneratedRuntime: Bool {
        generatedRuntimeUnsupportedReason == nil
    }

    var generatedRuntimeUnsupportedReason: String? {
        if let unsupportedReason {
            return unsupportedReason
        }
        guard states.isEmpty else {
            return "Generated invocation does not manage mutable Core AI state."
        }
        for input in inputs {
            switch input.kind {
            case .tensor:
                continue
            case .image:
                return "Generated invocation accepts NDArray inputs only; input \(input.name) is an image."
            case .unknown:
                return "Generated invocation cannot safely represent unknown input \(input.name)."
            }
        }
        return nil
    }
}
