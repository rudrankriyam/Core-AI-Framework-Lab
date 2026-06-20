import CoreAI
import Foundation

enum CoreAIFunctionContractBuilder {
    static func contracts(for model: AIModel) -> [CoreAIFunctionContract] {
        model.functionNames.sorted().map { name in
            guard let descriptor = model.functionDescriptor(for: name) else {
                return CoreAIFunctionContract(
                    name: name,
                    inputs: [],
                    states: [],
                    outputs: [],
                    unsupportedReason: "Core AI did not provide a descriptor for this function."
                )
            }
            return contract(descriptor)
        }
    }

    private static func contract(
        _ descriptor: InferenceFunctionDescriptor
    ) -> CoreAIFunctionContract {
        let inputs = descriptor.inputNames.map { name in
            valueContract(
                name: name,
                descriptor: descriptor.inputDescriptor(of: name)
            )
        }
        let states = descriptor.stateNames.map { name in
            valueContract(
                name: name,
                descriptor: descriptor.stateDescriptor(of: name)
            )
        }
        let outputs = descriptor.outputNames.map { name in
            valueContract(
                name: name,
                descriptor: descriptor.outputDescriptor(of: name)
            )
        }
        return CoreAIFunctionContract(
            name: descriptor.name,
            inputs: inputs,
            states: states,
            outputs: outputs,
            unsupportedReason: unsupportedReason(inputs: inputs, states: states)
        )
    }

    private static func valueContract(
        name: String,
        descriptor: InferenceValue.Descriptor?
    ) -> CoreAIFunctionValueContract {
        guard let descriptor else {
            return CoreAIFunctionValueContract(name: name, kind: .unknown)
        }
        switch descriptor {
        case .ndArray(let tensor):
            return CoreAIFunctionValueContract(
                name: name,
                kind: .tensor(
                    CoreAITensorContract(
                        scalarType: tensor.scalarType,
                        shape: tensor.shape,
                        hasDynamicShape: tensor.hasDynamicShape,
                        minimumByteCount: tensor.minimumByteCount
                    )
                )
            )
        case .image(let image):
            return CoreAIFunctionValueContract(
                name: name,
                kind: .image(
                    CoreAIImageContract(
                        width: image.width,
                        height: image.height,
                        pixelFormatType: image.pixelFormatType
                    )
                )
            )
        @unknown default:
            return CoreAIFunctionValueContract(name: name, kind: .unknown)
        }
    }

    private static func unsupportedReason(
        inputs: [CoreAIFunctionValueContract],
        states: [CoreAIFunctionValueContract]
    ) -> String? {
        if !states.isEmpty {
            return "This function has mutable state. Generic state execution is not safe with the current Swift lifetime API; use a task adapter."
        }
        for input in inputs {
            switch input.kind {
            case .tensor(let tensor):
                if !CoreAITensorScalarSupport.isGeneratable(tensor.scalarType) {
                    return "Input \(input.name) uses unsupported scalar type \(tensor.scalarTypeName). The signature remains inspectable."
                }
            case .image:
                return "Input \(input.name) is an image. Generic image adaptation is not part of this first tensor workbench."
            case .unknown:
                return "Input \(input.name) has an unknown descriptor and cannot be generated safely."
            }
        }
        return nil
    }
}
