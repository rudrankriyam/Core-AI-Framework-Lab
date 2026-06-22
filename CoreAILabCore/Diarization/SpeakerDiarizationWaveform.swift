import Foundation

struct SpeakerDiarizationWaveform: Equatable, Sendable {
    let magnitudes: [Double]
    let durationSeconds: Double

    var isEmpty: Bool {
        magnitudes.isEmpty
    }
}
