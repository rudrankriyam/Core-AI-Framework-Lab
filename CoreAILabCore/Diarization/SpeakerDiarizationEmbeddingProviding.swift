import Foundation

protocol SpeakerDiarizationEmbeddingProviding: Sendable {
    func loadModel(at url: URL) async throws -> SpeakerDiarizationModelInfo
    func embedding(for features: SpeakerDiarizationFeatures) async throws -> [Float]
}
