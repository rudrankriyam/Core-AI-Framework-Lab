import Foundation

struct SpeakerDiarizationAudio: Sendable, Equatable {
    let samples: [Float]
    let sampleRate: Int

    var durationSeconds: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / Double(sampleRate)
    }
}
