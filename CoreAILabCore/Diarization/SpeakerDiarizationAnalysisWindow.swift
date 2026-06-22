import Foundation

struct SpeakerDiarizationAnalysisWindow: Sendable, Equatable {
    let timelineSampleRange: Range<Int>
    let featureSampleRange: Range<Int>

    func startTime(sampleRate: Int) -> Double {
        Double(timelineSampleRange.lowerBound) / Double(sampleRate)
    }

    func endTime(sampleRate: Int) -> Double {
        Double(timelineSampleRange.upperBound) / Double(sampleRate)
    }
}
