import CoreAI
import Foundation

struct CoreAIInferencePreparation: Sendable, Equatable {
    let functionName: String
    let inputNames: [String]
    let stateNames: [String]
    let outputNames: [String]
    let notes: [String]
}

enum CoreAIInferenceExamples {
    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func prepareFirstFunction(from model: AIModel) throws -> CoreAIInferencePreparation? {
        guard let functionName = model.functionNames.first,
              let function = try model.loadFunction(named: functionName) else {
            return nil
        }

        return prepare(function)
    }

    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func prepare(_ function: InferenceFunction) -> CoreAIInferencePreparation {
        let descriptor = function.descriptor
        return CoreAIInferencePreparation(
            functionName: descriptor.name,
            inputNames: descriptor.inputNames,
            stateNames: descriptor.stateNames,
            outputNames: descriptor.outputNames,
            notes: [
                "Create one NDArray or pixel-buffer value for each input descriptor.",
                "Use descriptor.inputDescriptor(of:) to choose tensor shape or image format.",
                "Call function.run(inputs:) for NDArray inputs once values match the descriptors.",
                "Use outputNames to read typed results from the returned outputs container."
            ]
        )
    }

    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func runNDArrayInputs(
        _ inputs: [String: NDArray],
        with function: InferenceFunction
    ) async throws -> InferenceFunction.Outputs {
        try await function.run(inputs: inputs)
    }
}
