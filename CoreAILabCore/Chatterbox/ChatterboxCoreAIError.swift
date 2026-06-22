import Foundation

enum ChatterboxCoreAIError: LocalizedError {
    case bundledResourcesMissing
    case unsafeResourcePath(String)
    case invalidModelAsset(String)
    case modelNotLoaded
    case emptyPrompt
    case textTooLong(tokenCount: Int, maximumTokenCount: Int)
    case generationLimitReached
    case missingEntrypoints(asset: String, names: [String])
    case tokenizerParityFailed
    case missingFunction(String)
    case missingOutput(String)
    case invalidOutputShape(String)
    case invalidWaveFile(String)
    case unsupportedScalarType(String)

    var errorDescription: String? {
        switch self {
        case .bundledResourcesMissing:
            "The bundled Chatterbox model resources are missing from this app build."
        case .unsafeResourcePath(let path):
            "The Chatterbox resource path is unsafe or escapes its bundle: \(path)."
        case .invalidModelAsset(let name):
            "\(name) is not a valid Core AI model asset."
        case .modelNotLoaded:
            "The bundled Chatterbox model has not finished preparing."
        case .emptyPrompt:
            "Enter some text for Chatterbox to speak."
        case .textTooLong(let tokenCount, let maximumTokenCount):
            "The prompt is \(tokenCount) tokens. This recipe supports at most \(maximumTokenCount) text tokens."
        case .generationLimitReached:
            "This utterance reached the recipe's speech-token capacity. Shorten the text and try again."
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
        case .invalidWaveFile(let message):
            message
        case .unsupportedScalarType(let scalarType):
            "Chatterbox received an unsupported Core AI scalar type: \(scalarType)."
        }
    }
}
