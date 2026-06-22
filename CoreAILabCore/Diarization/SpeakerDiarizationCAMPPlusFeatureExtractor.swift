import Accelerate
import Foundation

enum SpeakerDiarizationCAMPPlusFeatureExtractor {
    static let sampleRate = 16_000
    static let sampleCount = 96_240
    static let frameCount = 600
    static let binCount = 80

    private static let frameLength = 400
    private static let frameShift = 160
    private static let fftSize = 512
    private static let epsilon = Float.ulpOfOne
    private static let preemphasis: Float = 0.97
    private static let poveyWindow: [Float] = (0..<frameLength).map { index in
        let phase = (2 * Double.pi * Double(index)) / Double(frameLength - 1)
        return Float(pow(0.5 - (0.5 * cos(phase)), 0.85))
    }
    private static let melWeights = makeMelWeights()

    static func extract(samples: [Float]) throws -> SpeakerDiarizationFeatures {
        guard samples.count == sampleCount else {
            throw SpeakerDiarizationError.invalidFeatureInput(
                "expected \(sampleCount) samples, received \(samples.count)"
            )
        }
        let producedFrameCount = ((samples.count - frameLength) / frameShift) + 1
        guard producedFrameCount == frameCount else {
            throw SpeakerDiarizationError.invalidFeatureInput(
                "expected \(frameCount) frames, produced \(producedFrameCount)"
            )
        }

        var values = Array(
            repeating: Float.zero,
            count: frameCount * binCount
        )
        var columnSums = Array(repeating: Float.zero, count: binCount)
        var fftInput = Array(repeating: Float.zero, count: fftSize)
        let imaginaryInput = Array(repeating: Float.zero, count: fftSize)
        var real = Array(repeating: Float.zero, count: fftSize)
        var imaginary = Array(repeating: Float.zero, count: fftSize)
        var power = Array(repeating: Float.zero, count: (fftSize / 2) + 1)
        let transform: vDSP.DiscreteFourierTransform<Float>
        do {
            transform = try vDSP.DiscreteFourierTransform(
                count: fftSize,
                direction: .forward,
                transformType: .complexComplex,
                ofType: Float.self
            )
        } catch {
            throw SpeakerDiarizationError.invalidFeatureInput(
                "could not create the \(fftSize)-point Fourier transform"
            )
        }

        for frame in 0..<frameCount {
            let start = frame * frameShift
            var mean = Float.zero
            for index in 0..<frameLength {
                mean += samples[start + index]
            }
            mean /= Float(frameLength)

            for index in 0..<frameLength {
                let current = samples[start + index] - mean
                let previous = samples[start + max(0, index - 1)] - mean
                fftInput[index] = (current - (preemphasis * previous)) * poveyWindow[index]
            }
            for index in frameLength..<fftSize {
                fftInput[index] = 0
            }
            transform.transform(
                inputReal: fftInput,
                inputImaginary: imaginaryInput,
                outputReal: &real,
                outputImaginary: &imaginary
            )
            for index in power.indices {
                power[index] = (real[index] * real[index])
                    + (imaginary[index] * imaginary[index])
            }

            for bin in 0..<binCount {
                let energy = vDSP.dot(power[0..<(fftSize / 2)], melWeights[bin])
                let value = log(max(energy, epsilon))
                values[(frame * binCount) + bin] = value
                columnSums[bin] += value
            }
        }

        for bin in 0..<binCount {
            let mean = columnSums[bin] / Float(frameCount)
            for frame in 0..<frameCount {
                values[(frame * binCount) + bin] -= mean
            }
        }
        guard values.allSatisfy(\.isFinite) else {
            throw SpeakerDiarizationError.invalidFeatureInput(
                "filterbank produced a non-finite value"
            )
        }
        return SpeakerDiarizationFeatures(
            values: values,
            frameCount: frameCount,
            binCount: binCount
        )
    }

    private static func makeMelWeights() -> [[Float]] {
        let lowMel = melScale(20)
        let highMel = melScale(Double(sampleRate) / 2)
        let delta = (highMel - lowMel) / Double(binCount + 1)
        return (0..<binCount).map { bin in
            let left = lowMel + (Double(bin) * delta)
            let center = lowMel + (Double(bin + 1) * delta)
            let right = lowMel + (Double(bin + 2) * delta)
            return (0..<(fftSize / 2)).map { fftBin in
                let frequency = Double(fftBin * sampleRate) / Double(fftSize)
                let mel = melScale(frequency)
                let upward = (mel - left) / (center - left)
                let downward = (right - mel) / (right - center)
                return Float(max(0, min(upward, downward)))
            }
        }
    }

    private static func melScale(_ frequency: Double) -> Double {
        1_127 * log(1 + (frequency / 700))
    }
}
