import Foundation

struct SpeakerDiarizationMediaSummary: Equatable, Sendable {
    let fileName: String
    let kind: SpeakerDiarizationMediaKind
    let durationSeconds: Double
    let sampleRate: Double
    let channelCount: Int
}
