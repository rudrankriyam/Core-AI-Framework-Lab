import Foundation

enum SpeakerDiarizationError: LocalizedError {
    case missingAudioTrack
    case readerFailed(String)
    case unsupportedSampleBuffer
    case unreadableDuration
    case unexpectedDecodedFormat(sampleRate: Double, channelCount: Int)
    case missingAudioSamples
    case modelNotLoaded
    case missingFunction(String)
    case invalidModelContract(String)
    case unsupportedScalarType(String)
    case invalidFeatureInput(String)
    case missingOutput(String)
    case invalidEmbedding(String)

    var errorDescription: String? {
        switch self {
        case .missingAudioTrack:
            "The selected file does not contain a readable audio track."
        case .readerFailed(let reason):
            "The media reader failed: \(reason)"
        case .unsupportedSampleBuffer:
            "The audio track could not be decoded into floating point samples."
        case .unreadableDuration:
            "The media duration could not be read."
        case .unexpectedDecodedFormat(let sampleRate, let channelCount):
            "Expected 16 kHz mono audio, but decoded \(sampleRate.formatted()) Hz with \(channelCount.formatted()) channels."
        case .missingAudioSamples:
            "The selected media did not decode into any audio samples."
        case .modelNotLoaded:
            "Import the converted CAM++ Core AI model before running diarization."
        case .missingFunction(let name):
            "The CAM++ asset does not contain its required `\(name)` function."
        case .invalidModelContract(let detail):
            "The CAM++ model contract is unsupported: \(detail)"
        case .unsupportedScalarType(let type):
            "CAM++ uses unsupported scalar type \(type). Export Float16 or Float32."
        case .invalidFeatureInput(let detail):
            "CAM++ feature extraction failed: \(detail)"
        case .missingOutput(let name):
            "CAM++ did not return its `\(name)` output."
        case .invalidEmbedding(let detail):
            "CAM++ returned an invalid speaker embedding: \(detail)"
        }
    }
}
