import AVFoundation
import Foundation

struct AppleAudioSamples: Sendable {
    let values: [Float]
    let durationSeconds: Double
}

enum AppleAudioSampleLoader {
    static let sampleRate = 16_000.0

    static func loadMono16k(
        from url: URL,
        maximumDurationSeconds: Double
    ) throws -> AppleAudioSamples {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let duration = Double(file.length) / sourceFormat.sampleRate
        guard duration <= maximumDurationSeconds else {
            throw AppleAudioError.audioTooLong(maximumSeconds: maximumDurationSeconds)
        }
        guard let monoSourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: 1,
            interleaved: false
        ), let destinationFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AppleAudioError.audioConversionFailed
        }

        let inputCapacity = AVAudioFrameCount(file.length)
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: inputCapacity
        ) else {
            throw AppleAudioError.audioConversionFailed
        }
        try file.read(into: inputBuffer)

        guard let sourceChannels = inputBuffer.floatChannelData,
              let monoBuffer = AVAudioPCMBuffer(
                  pcmFormat: monoSourceFormat,
                  frameCapacity: inputBuffer.frameLength
              ), let monoChannel = monoBuffer.floatChannelData?[0] else {
            throw AppleAudioError.audioConversionFailed
        }
        monoBuffer.frameLength = inputBuffer.frameLength
        let channelCount = Int(sourceFormat.channelCount)
        for frame in 0..<Int(inputBuffer.frameLength) {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += sourceChannels[channel][frame]
            }
            monoChannel[frame] = sum / Float(channelCount)
        }

        if sourceFormat.sampleRate == sampleRate {
            let frameCount = Int(monoBuffer.frameLength)
            return AppleAudioSamples(
                values: Array(UnsafeBufferPointer(start: monoChannel, count: frameCount)),
                durationSeconds: Double(frameCount) / sampleRate
            )
        }

        guard let converter = AVAudioConverter(
            from: monoSourceFormat,
            to: destinationFormat
        ) else {
            throw AppleAudioError.audioConversionFailed
        }

        let estimatedFrames = ceil(Double(monoBuffer.frameLength) * sampleRate / sourceFormat.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: destinationFormat,
            frameCapacity: AVAudioFrameCount(estimatedFrames + 32)
        ) else {
            throw AppleAudioError.audioConversionFailed
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) {
            _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return monoBuffer
        }
        guard status == .haveData || status == .endOfStream,
              conversionError == nil,
              let channel = outputBuffer.floatChannelData?[0] else {
            throw conversionError ?? AppleAudioError.audioConversionFailed
        }

        let frameCount = Int(outputBuffer.frameLength)
        return AppleAudioSamples(
            values: Array(UnsafeBufferPointer(start: channel, count: frameCount)),
            durationSeconds: Double(frameCount) / sampleRate
        )
    }
}
