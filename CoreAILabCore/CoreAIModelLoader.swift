import CoreAI
import Foundation

enum CoreAIModelLoader {
    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func specializeModel(at url: URL, prefer preferredComputeUnit: ComputeUnitKind? = nil) async throws -> AIModel {
        let options: SpecializationOptions
        if let preferredComputeUnit {
            options = SpecializationOptions(preferredComputeUnitKind: preferredComputeUnit)
        } else {
            options = .default
        }

        return try await AIModel.specialize(
            contentsOf: url,
            options: options,
            cache: .default,
            cachePolicy: .default
        )
    }

    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func loadFunction(named functionName: String, from model: AIModel) throws -> InferenceFunction? {
        try model.loadFunction(named: functionName)
    }
}

