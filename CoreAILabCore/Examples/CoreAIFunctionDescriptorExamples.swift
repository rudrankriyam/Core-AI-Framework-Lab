import CoreAI
import Foundation

struct CoreAIFunctionDescriptorReport: Sendable, Equatable {
    let name: String
    let inputNames: [String]
    let stateNames: [String]
    let outputNames: [String]
    let inputDescriptions: [String: String]
    let stateDescriptions: [String: String]
    let outputDescriptions: [String: String]
}

enum CoreAIFunctionDescriptorExamples {
    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func report(for descriptor: InferenceFunctionDescriptor) -> CoreAIFunctionDescriptorReport {
        CoreAIFunctionDescriptorReport(
            name: descriptor.name,
            inputNames: descriptor.inputNames,
            stateNames: descriptor.stateNames,
            outputNames: descriptor.outputNames,
            inputDescriptions: descriptions(
                names: descriptor.inputNames,
                descriptorForName: descriptor.inputDescriptor(of:)
            ),
            stateDescriptions: descriptions(
                names: descriptor.stateNames,
                descriptorForName: descriptor.stateDescriptor(of:)
            ),
            outputDescriptions: descriptions(
                names: descriptor.outputNames,
                descriptorForName: descriptor.outputDescriptor(of:)
            )
        )
    }

    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func reports(for model: AIModel) -> [CoreAIFunctionDescriptorReport] {
        model.functionNames.compactMap { name in
            model.functionDescriptor(for: name).map(report(for:))
        }
    }

    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    private static func descriptions(
        names: [String],
        descriptorForName: (String) -> InferenceValue.Descriptor?
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: names.map { name in
            (name, descriptorForName(name).map(CoreAIValueDescriptorExamples.describe) ?? "unknown")
        })
    }
}
