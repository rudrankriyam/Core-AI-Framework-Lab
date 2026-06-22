import Foundation

struct SpeakerDiarizationMediaAnalysis: Equatable, Sendable {
    let summary: SpeakerDiarizationMediaSummary
    let waveform: SpeakerDiarizationWaveform
}
