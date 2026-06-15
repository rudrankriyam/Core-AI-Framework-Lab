import Foundation

enum ChatterboxCoreAIError: LocalizedError {
    case bundledResourcesMissing
    case invalidModelAsset(String)
    case modelNotLoaded
    case emptyPrompt
    case textTooLong(Int)
    case generationLimitReached
    case missingEntrypoints(asset: String, names: [String])
    case tokenizerParityFailed
    case missingFunction(String)
    case missingOutput(String)
    case invalidOutputShape(String)
    case unsupportedScalarType(String)

    var errorDescription: String? {
        switch self {
        case .bundledResourcesMissing:
            "The bundled Chatterbox model resources are missing from this app build."
        case .invalidModelAsset(let name):
            "\(name) is not a valid Core AI model asset."
        case .modelNotLoaded:
            "The bundled Chatterbox model has not finished preparing."
        case .emptyPrompt:
            "Enter some text for Chatterbox to speak."
        case .textTooLong(let tokenCount):
            "The prompt is \(tokenCount) tokens. Chatterbox currently supports at most 256 text tokens."
        case .generationLimitReached:
            "This utterance needs more than the current 10-second Core AI graph window. Shorten the text and try again."
        case .missingEntrypoints(let asset, let names):
            "\(asset) is missing required entry points: \(names.joined(separator: ", "))."
        case .tokenizerParityFailed:
            "The bundled Swift tokenizer does not match Chatterbox's source tokenizer."
        case .missingFunction(let name):
            "The Core AI function \(name) could not be loaded."
        case .missingOutput(let name):
            "The Core AI function did not return its \(name) output."
        case .invalidOutputShape(let message):
            message
        case .unsupportedScalarType(let scalarType):
            "Chatterbox received an unsupported Core AI scalar type: \(scalarType)."
        }
    }
}
