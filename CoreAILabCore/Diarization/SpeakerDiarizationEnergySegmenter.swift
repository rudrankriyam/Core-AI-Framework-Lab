import Foundation

struct SpeakerDiarizationEnergySegmenter: Sendable {
    private let frameLengthSeconds = 0.03
    private let frameShiftSeconds = 0.01
    private let minimumSpeechSeconds = 0.20
    private let maximumBridgedSilenceSeconds = 0.75
    private let paddingSeconds = 0.10
    private let minimumPeakDecibels = -55.0

    func regions(in audio: SpeakerDiarizationAudio) -> [SpeakerDiarizationSpeechRegion] {
        let frameLength = max(1, Int(frameLengthSeconds * Double(audio.sampleRate)))
        let frameShift = max(1, Int(frameShiftSeconds * Double(audio.sampleRate)))
        guard audio.samples.count >= frameLength else {
            return shortAudioRegion(audio: audio)
        }

        var energies: [Double] = []
        energies.reserveCapacity((audio.samples.count - frameLength) / frameShift + 1)
        var start = 0
        while start + frameLength <= audio.samples.count {
            var sumOfSquares = Double.zero
            for sample in audio.samples[start..<(start + frameLength)] {
                let value = Double(sample)
                sumOfSquares += value * value
            }
            let rms = sqrt(sumOfSquares / Double(frameLength))
            energies.append(20 * log10(max(rms, 1e-12)))
            start += frameShift
        }

        let ordered = energies.sorted()
        guard let peak = percentile(0.95, in: ordered), peak > minimumPeakDecibels,
              let noiseFloor = percentile(0.20, in: ordered) else {
            return []
        }
        let threshold = min(noiseFloor + 10, peak - 3)
        let activeFrames = energies.indices.filter { energies[$0] >= threshold }
        guard !activeFrames.isEmpty else { return [] }

        let maximumGap = max(
            1,
            Int(maximumBridgedSilenceSeconds / frameShiftSeconds)
        )
        var runs: [Range<Int>] = []
        var runStart = activeFrames[0]
        var previous = activeFrames[0]
        for frame in activeFrames.dropFirst() {
            if frame - previous > maximumGap {
                runs.append(runStart..<(previous + 1))
                runStart = frame
            }
            previous = frame
        }
        runs.append(runStart..<(previous + 1))

        let minimumFrames = max(1, Int(minimumSpeechSeconds / frameShiftSeconds))
        let paddingFrames = max(0, Int(paddingSeconds / frameShiftSeconds))
        return runs.compactMap { run in
            guard run.count >= minimumFrames else { return nil }
            let firstFrame = max(0, run.lowerBound - paddingFrames)
            let finalFrame = min(energies.count, run.upperBound + paddingFrames)
            let firstSample = firstFrame * frameShift
            let finalSample = min(
                audio.samples.count,
                ((finalFrame - 1) * frameShift) + frameLength
            )
            return SpeakerDiarizationSpeechRegion(
                sampleRange: firstSample..<finalSample
            )
        }
    }

    private func shortAudioRegion(
        audio: SpeakerDiarizationAudio
    ) -> [SpeakerDiarizationSpeechRegion] {
        guard !audio.samples.isEmpty else { return [] }
        var sumOfSquares = Double.zero
        for sample in audio.samples {
            let value = Double(sample)
            sumOfSquares += value * value
        }
        let rms = sqrt(sumOfSquares / Double(audio.samples.count))
        guard 20 * log10(max(rms, 1e-12)) > minimumPeakDecibels else {
            return []
        }
        return [SpeakerDiarizationSpeechRegion(sampleRange: 0..<audio.samples.count)]
    }

    private func percentile(_ quantile: Double, in values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let index = min(
            values.count - 1,
            max(0, Int((Double(values.count - 1) * quantile).rounded(.down)))
        )
        return values[index]
    }
}
