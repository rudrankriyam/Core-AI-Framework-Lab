import Foundation

enum SpeakerDiarizationError: LocalizedError {
    case missingAudioTrack
    case readerFailed(String)
    case unsupportedSampleBuffer
    case unreadableDuration

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
        }
    }
}
