import Foundation

struct SpeakerDiarizationSpeechRegion: Sendable, Equatable {
    let sampleRange: Range<Int>

    func startTime(sampleRate: Int) -> Double {
        Double(sampleRange.lowerBound) / Double(sampleRate)
    }

    func endTime(sampleRate: Int) -> Double {
        Double(sampleRange.upperBound) / Double(sampleRate)
    }
}
