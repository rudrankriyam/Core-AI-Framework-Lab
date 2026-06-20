import Foundation

struct CoreAIExportManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let artifact: Artifact
    let metadata: Metadata
    let specialization: Specialization
    let functions: [Function]

    init(
        artifact: Artifact,
        report: CoreAIModelAssetReport,
        specializationProfile: CoreAISpecializationProfile,
        expectFrequentReshapes: Bool = false,
        contracts: [CoreAIFunctionContract]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.artifact = artifact
        metadata = Metadata(
            author: report.author,
            license: report.license,
            description: report.description,
            computeTypes: report.computeTypes.sorted()
        )
        specialization = Specialization(
            profile: specializationProfile,
            expectFrequentReshapes: expectFrequentReshapes
        )
        functions = contracts.sorted { $0.name < $1.name }.map(Function.init)
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
        let runtimeEnforcesCPUOnly: Bool

        init(profile: CoreAISpecializationProfile, expectFrequentReshapes: Bool) {
            self.profile = profile.rawValue
            self.expectFrequentReshapes = expectFrequentReshapes
            runtimeEnforcesCPUOnly = profile == .cpuOnly
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
