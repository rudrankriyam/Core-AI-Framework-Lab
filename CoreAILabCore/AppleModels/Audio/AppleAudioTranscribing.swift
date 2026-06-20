import Foundation

struct AppleAudioModelInfo: Equatable, Sendable {
    let sampleCount: Int
    let sampleRate: Double
    let scalarTypeName: String
}

struct AppleAudioTranscriptionResult: Equatable, Sendable {
    let transcript: String
    let audioDurationSeconds: Double
    let inferenceDurationSeconds: Double
}

protocol AppleAudioTranscribing: Sendable {
    func loadModel(at url: URL) async throws -> AppleAudioModelInfo
    func transcribe(audioAt url: URL) async throws -> AppleAudioTranscriptionResult
}
