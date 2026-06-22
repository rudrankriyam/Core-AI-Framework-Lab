import AVFoundation
import Foundation

enum SpeakerDiarizationAudioDecoder {
    static let sampleRate = 16_000

    static func decode(url: URL) async throws -> SpeakerDiarizationAudio {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw SpeakerDiarizationError.missingAudioTrack
        }
        let duration = try await asset.load(.duration).seconds

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        let provider = reader.outputProvider(for: output)
        try reader.start()

        var samples: [Float] = []
        if duration.isFinite, duration > 0 {
            samples.reserveCapacity(
                min(Int(duration * Double(sampleRate)), sampleRate * 300)
            )
        }

        while let readySampleBuffer = try await provider.next() {
            try Task.checkCancellation()
            try readySampleBuffer.withUnsafeSampleBuffer { sampleBuffer in
                guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
                      let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                          formatDescription
                      ), let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                    throw SpeakerDiarizationError.unsupportedSampleBuffer
                }
                let description = streamDescription.pointee
                guard Int(description.mSampleRate.rounded()) == sampleRate,
                      description.mChannelsPerFrame == 1 else {
                    throw SpeakerDiarizationError.unexpectedDecodedFormat(
                        sampleRate: description.mSampleRate,
                        channelCount: Int(description.mChannelsPerFrame)
                    )
                }

                var length = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                let status = CMBlockBufferGetDataPointer(
                    blockBuffer,
                    atOffset: 0,
                    lengthAtOffsetOut: nil,
                    totalLengthOut: &length,
                    dataPointerOut: &dataPointer
                )
                guard status == noErr, let dataPointer else {
                    throw SpeakerDiarizationError.unsupportedSampleBuffer
                }
                let sampleCount = length / MemoryLayout<Float>.stride
                dataPointer.withMemoryRebound(to: Float.self, capacity: sampleCount) {
                    samples.append(
                        contentsOf: UnsafeBufferPointer(start: $0, count: sampleCount)
                    )
                }
            }
        }

        guard reader.status == .completed else {
            throw SpeakerDiarizationError.readerFailed(
                reader.error?.localizedDescription ?? "unknown error"
            )
        }
        guard !samples.isEmpty else {
            throw SpeakerDiarizationError.missingAudioSamples
        }
        return SpeakerDiarizationAudio(samples: samples, sampleRate: sampleRate)
    }
}
