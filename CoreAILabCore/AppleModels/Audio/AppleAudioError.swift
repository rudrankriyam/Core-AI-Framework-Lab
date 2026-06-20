import Foundation

enum AppleAudioError: LocalizedError {
    case modelNotLoaded
    case missingFunction(String)
    case invalidInputContract(String)
    case invalidOutputContract(String)
    case missingOutput(String)
    case unsupportedScalarType(String)
    case audioTooLong(maximumSeconds: Double)
    case audioConversionFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            "Import Apple's exported Wav2Vec2 `.aimodel` before transcribing."
        case .missingFunction(let name):
            "The Wav2Vec2 asset does not contain its required `\(name)` function."
        case .invalidInputContract(let detail):
            "The Wav2Vec2 input contract is unsupported: \(detail)"
        case .invalidOutputContract(let detail):
            "The Wav2Vec2 output contract is unsupported: \(detail)"
        case .missingOutput(let name):
            "Wav2Vec2 did not return its `\(name)` output."
        case .unsupportedScalarType(let type):
            "Wav2Vec2 uses unsupported scalar type \(type). Export Float16 or Float32."
        case .audioTooLong(let maximumSeconds):
            "Choose audio no longer than \(maximumSeconds.formatted()) seconds for Apple's static Wav2Vec2 recipe."
        case .audioConversionFailed:
            "The selected audio could not be decoded as 16 kHz mono PCM."
        }
    }
}
