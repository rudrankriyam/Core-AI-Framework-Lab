import Foundation

struct SpeakerDiarizationWindowBuilder: Sendable {
    static let timelineWindowSeconds = 3.0

    func windows(
        for regions: [SpeakerDiarizationSpeechRegion],
        sampleRate: Int
    ) -> [SpeakerDiarizationAnalysisWindow] {
        let maximumSamples = max(1, Int(Self.timelineWindowSeconds * Double(sampleRate)))
        let modelSampleCount = SpeakerDiarizationCAMPPlusFeatureExtractor.sampleCount
        return regions.flatMap { region in
            var result: [SpeakerDiarizationAnalysisWindow] = []
            var start = region.sampleRange.lowerBound
            while start < region.sampleRange.upperBound {
                let end = min(start + maximumSamples, region.sampleRange.upperBound)
                result.append(
                    SpeakerDiarizationAnalysisWindow(
                        timelineSampleRange: start..<end,
                        featureSampleRange: featureRange(
                            centeredOn: start..<end,
                            within: region.sampleRange,
                            sampleCount: modelSampleCount
                        )
                    )
                )
                start = end
            }
            return result
        }
    }

    func modelSamples(
        for window: SpeakerDiarizationAnalysisWindow,
        audio: SpeakerDiarizationAudio,
        sampleCount: Int
    ) throws -> [Float] {
        let range = window.featureSampleRange.clamped(to: audio.samples.indices)
        guard !range.isEmpty else {
            throw SpeakerDiarizationError.missingAudioSamples
        }
        var result = Array(repeating: Float.zero, count: sampleCount)
        for index in result.indices {
            result[index] = audio.samples[range.lowerBound + (index % range.count)]
        }
        return result
    }

    private func featureRange(
        centeredOn timelineRange: Range<Int>,
        within regionRange: Range<Int>,
        sampleCount: Int
    ) -> Range<Int> {
        guard regionRange.count > sampleCount else {
            return regionRange
        }
        let midpoint = timelineRange.lowerBound + (timelineRange.count / 2)
        let proposedStart = midpoint - (sampleCount / 2)
        let start = min(
            max(proposedStart, regionRange.lowerBound),
            regionRange.upperBound - sampleCount
        )
        return start..<(start + sampleCount)
    }
}
