import CoreAI
import Foundation

enum CoreAITensorShapeValidator {
    static let defaultAllocationLimit = 256 * 1_024 * 1_024

    static func resolve(
        descriptor: NDArrayDescriptor,
        requestedShape: [Int],
        inputName: String,
        allocationLimit: Int = defaultAllocationLimit
    ) throws -> NDArrayDescriptor {
        guard requestedShape.count == descriptor.rank else {
            throw CoreAIFunctionWorkbenchError.invalidShape(
                name: inputName,
                reason: "expected rank \(descriptor.rank), got \(requestedShape.count)."
            )
        }
        guard requestedShape.allSatisfy({ $0 > 0 }) else {
            throw CoreAIFunctionWorkbenchError.invalidShape(
                name: inputName,
                reason: "every dimension must be greater than zero."
            )
        }

        if descriptor.hasDynamicShape {
            for (declared, requested) in zip(descriptor.shape, requestedShape)
                where declared > 0 && declared != requested {
                throw CoreAIFunctionWorkbenchError.invalidShape(
                    name: inputName,
                    reason: "fixed dimension \(declared) cannot be changed to \(requested)."
                )
            }
        } else if descriptor.shape != requestedShape {
            throw CoreAIFunctionWorkbenchError.invalidShape(
                name: inputName,
                reason: "the function requires \(descriptor.shape)."
            )
        }

        let resolved = descriptor.hasDynamicShape
            ? descriptor.resolvingDynamicDimensions(requestedShape)
            : descriptor
        guard resolved.minimumByteCount <= allocationLimit else {
            throw CoreAIFunctionWorkbenchError.allocationTooLarge(
                name: inputName,
                bytes: resolved.minimumByteCount,
                limit: allocationLimit
            )
        }
        return resolved
    }
}
