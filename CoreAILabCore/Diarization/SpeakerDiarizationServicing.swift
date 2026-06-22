import Foundation

protocol SpeakerDiarizationServicing: Sendable {
    func loadModel(at url: URL) async throws -> SpeakerDiarizationModelInfo
    func diarize(mediaAt url: URL) async throws -> SpeakerDiarizationResult
}
