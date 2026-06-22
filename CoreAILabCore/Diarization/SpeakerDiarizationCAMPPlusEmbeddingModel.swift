import CoreAI
import Foundation

actor SpeakerDiarizationCAMPPlusEmbeddingModel: SpeakerDiarizationEmbeddingProviding {
    private enum InputPrecision {
        case float16
        case float32

        var name: String {
            switch self {
            case .float16: "float16"
            case .float32: "float32"
            }
        }
    }

    private struct LoadedModel {
        let model: AIModel
        let function: InferenceFunction
        let info: SpeakerDiarizationModelInfo
        let precision: InputPrecision
    }

    private var loadedModel: LoadedModel?

    func loadModel(at url: URL) async throws -> SpeakerDiarizationModelInfo {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let model = try await AIModel.specialize(
            contentsOf: url,
            options: .default,
            cache: .default,
            cachePolicy: .persistent
        )
        guard let function = try model.loadFunction(named: "main") else {
            throw SpeakerDiarizationError.missingFunction("main")
        }
        let descriptor = function.descriptor
        guard descriptor.stateNames.isEmpty else {
            throw SpeakerDiarizationError.invalidModelContract(
                "the main function must be stateless"
            )
        }
        guard case .ndArray(let input)? = descriptor.inputDescriptor(of: "features"),
              !input.hasDynamicShape,
              input.shape.count == 3,
              input.shape[0] == 1,
              input.shape[1] == SpeakerDiarizationCAMPPlusFeatureExtractor.frameCount,
              input.shape[2] == SpeakerDiarizationCAMPPlusFeatureExtractor.binCount else {
            throw SpeakerDiarizationError.invalidModelContract(
                "expected `features` shaped [1, 600, 80]"
            )
        }
        let precision: InputPrecision
        switch input.scalarType {
        case .float16:
            precision = .float16
        case .float32:
            precision = .float32
        default:
            throw SpeakerDiarizationError.unsupportedScalarType(
                String(describing: input.scalarType)
            )
        }
        guard case .ndArray(let output)? = descriptor.outputDescriptor(of: "embedding"),
              output.shape.count == 2,
              output.shape[0] == 1,
              output.shape[1] > 0,
              !output.hasDynamicShape,
              output.scalarType == .float16 || output.scalarType == .float32 else {
            throw SpeakerDiarizationError.invalidModelContract(
                "expected a floating-point `embedding` shaped [1, dimension]"
            )
        }

        let info = SpeakerDiarizationModelInfo(
            assetName: url.lastPathComponent,
            frameCount: input.shape[1],
            featureBinCount: input.shape[2],
            embeddingDimension: output.shape[1],
            scalarTypeName: precision.name
        )
        loadedModel = LoadedModel(
            model: model,
            function: function,
            info: info,
            precision: precision
        )
        return info
    }

    func embedding(for features: SpeakerDiarizationFeatures) async throws -> [Float] {
        guard let loadedModel else {
            throw SpeakerDiarizationError.modelNotLoaded
        }
        guard features.frameCount == loadedModel.info.frameCount,
              features.binCount == loadedModel.info.featureBinCount,
              features.values.count == features.frameCount * features.binCount else {
            throw SpeakerDiarizationError.invalidFeatureInput(
                "feature shape does not match the imported CAM++ asset"
            )
        }

        let input = makeInput(
            features: features,
            precision: loadedModel.precision
        )
        var outputs = try await loadedModel.function.run(inputs: ["features": input])
        guard let output = outputs.remove("embedding")?.ndArray else {
            throw SpeakerDiarizationError.missingOutput("embedding")
        }
        let values = try read(output)
        guard values.count == loadedModel.info.embeddingDimension else {
            throw SpeakerDiarizationError.invalidEmbedding(
                "expected \(loadedModel.info.embeddingDimension) values, received \(values.count)"
            )
        }
        return values
    }

    private func makeInput(
        features: SpeakerDiarizationFeatures,
        precision: InputPrecision
    ) -> NDArray {
        var array: NDArray
        switch precision {
        case .float16:
            array = NDArray(
                shape: [1, features.frameCount, features.binCount],
                scalarType: .float16
            )
            fill(&array, values: features.values, as: Float16.self)
        case .float32:
            array = NDArray(
                shape: [1, features.frameCount, features.binCount],
                scalarType: .float32
            )
            fill(&array, values: features.values, as: Float.self)
        }
        return array
    }

    private func fill<Element>(
        _ array: inout NDArray,
        values: [Float],
        as type: Element.Type
    ) where Element: BinaryFloatingPoint & BitwiseCopyable {
        var view = array.mutableView(as: type)
        view.withUnsafeMutablePointer { pointer, shape, strides in
            let dimensions = (0..<shape.count).map { shape[$0] }
            for flatIndex in values.indices {
                pointer[offset(for: flatIndex, shape: dimensions, strides: strides)] =
                    Element(values[flatIndex])
            }
        }
    }

    private func read(_ array: NDArray) throws -> [Float] {
        switch array.scalarType {
        case .float16:
            read(array, as: Float16.self)
        case .float32:
            read(array, as: Float.self)
        default:
            throw SpeakerDiarizationError.unsupportedScalarType(
                String(describing: array.scalarType)
            )
        }
    }

    private func read<Element>(
        _ array: NDArray,
        as type: Element.Type
    ) -> [Float] where Element: BinaryFloatingPoint & BitwiseCopyable {
        array.view(as: type).withUnsafePointer { pointer, shape, strides in
            let dimensions = (0..<shape.count).map { shape[$0] }
            let count = dimensions.reduce(1, *)
            return (0..<count).map { flatIndex in
                Float(pointer[offset(for: flatIndex, shape: dimensions, strides: strides)])
            }
        }
    }

    private func offset(
        for flatIndex: Int,
        shape: [Int],
        strides: Span<Int>
    ) -> Int {
        var remaining = flatIndex
        var offset = 0
        for dimension in shape.indices.reversed() {
            let coordinate = remaining % shape[dimension]
            remaining /= shape[dimension]
            offset += coordinate * strides[dimension]
        }
        return offset
    }
}
