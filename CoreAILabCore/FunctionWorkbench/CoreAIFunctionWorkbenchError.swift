import Foundation

enum CoreAIFunctionWorkbenchError: LocalizedError {
    case modelNotPrepared
    case functionUnavailable(String)
    case functionAlreadyRunning
    case unsupportedFunction(String)
    case missingInput(String)
    case invalidShape(name: String, reason: String)
    case allocationTooLarge(name: String, bytes: Int, limit: Int)
    case unsupportedScalarType(String)
    case missingOutput(String)

    var errorDescription: String? {
        switch self {
        case .modelNotPrepared:
            "Specialize the model before running a function."
        case .functionUnavailable(let name):
            "The Core AI function \(name) could not be loaded."
        case .functionAlreadyRunning:
            "A Core AI function is already running."
        case .unsupportedFunction(let reason):
            reason
        case .missingInput(let name):
            "No generated input was configured for \(name)."
        case .invalidShape(let name, let reason):
            "The shape for \(name) is invalid: \(reason)"
        case .allocationTooLarge(let name, let bytes, let limit):
            "The generated input \(name) requires at least \(bytes.formatted(.byteCount(style: .memory))) but the workbench limit is \(limit.formatted(.byteCount(style: .memory)))."
        case .unsupportedScalarType(let type):
            "The workbench cannot generate values for Core AI scalar type \(type)."
        case .missingOutput(let name):
            "Core AI did not return its declared \(name) output."
        }
    }
}
