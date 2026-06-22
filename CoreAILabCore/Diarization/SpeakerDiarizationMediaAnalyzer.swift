import AVFoundation
import Foundation

enum SpeakerDiarizationMediaAnalyzer {
    static func analyze(
        url: URL,
        bucketCount: Int = 96
    ) async throws -> SpeakerDiarizationMediaAnalysis {
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

        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw SpeakerDiarizationError.unreadableDuration
        }

        let waveform = try await makeWaveform(
            asset: asset,
            audioTrack: audioTrack,
            durationSeconds: durationSeconds,
            bucketCount: bucketCount
        )
        let format = try await audioTrack.load(.formatDescriptions)
            .compactMap { description in
                CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
            }
            .first

        let summary = SpeakerDiarizationMediaSummary(
            fileName: url.lastPathComponent,
            kind: try await asset.loadTracks(withMediaType: .video).isEmpty ? .audio : .video,
            durationSeconds: durationSeconds,
            sampleRate: format?.mSampleRate ?? 0,
            channelCount: Int(format?.mChannelsPerFrame ?? 0)
        )

        return SpeakerDiarizationMediaAnalysis(
            summary: summary,
            waveform: waveform
        )
    }

    private static func makeWaveform(
        asset: AVAsset,
        audioTrack: AVAssetTrack,
        durationSeconds: Double,
        bucketCount: Int
    ) async throws -> SpeakerDiarizationWaveform {
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: outputSettings
        )
        let provider = reader.outputProvider(for: output)
        try reader.start()

        let bucketCount = max(1, bucketCount)
        var peaks = Array(repeating: Double.zero, count: bucketCount)
        var sampleRate = Double.zero
        var channelCount = 1
        var frameIndex = 0

        while let readySampleBuffer = try await provider.next() {
            try Task.checkCancellation()
            try readySampleBuffer.withUnsafeSampleBuffer { sampleBuffer in
                guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
                      let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                          formatDescription
                      ), let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                    throw SpeakerDiarizationError.unsupportedSampleBuffer
                }
                let audioDescription = streamDescription.pointee
                sampleRate = audioDescription.mSampleRate
                channelCount = max(1, Int(audioDescription.mChannelsPerFrame))

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
                let samples = dataPointer.withMemoryRebound(
                    to: Float.self,
                    capacity: sampleCount
                ) { pointer in
                    UnsafeBufferPointer(start: pointer, count: sampleCount)
                }
                let frameCount = sampleCount / channelCount
                let estimatedTotalFrames = max(1, Int(durationSeconds * sampleRate))
                for frame in 0..<frameCount {
                    var magnitude = Double.zero
                    for channel in 0..<channelCount {
                        magnitude += Double(abs(samples[(frame * channelCount) + channel]))
                    }
                    magnitude /= Double(channelCount)
                    let bucket = min(
                        bucketCount - 1,
                        (frameIndex + frame) * bucketCount / estimatedTotalFrames
                    )
                    peaks[bucket] = max(peaks[bucket], magnitude)
                }
                frameIndex += frameCount
            }
        }

        guard reader.status == .completed else {
            throw SpeakerDiarizationError.readerFailed(
                reader.error?.localizedDescription ?? "unknown error"
            )
        }

        let maximum = peaks.max() ?? 0
        let normalized = maximum > 0 ? peaks.map { $0 / maximum } : peaks
        return SpeakerDiarizationWaveform(
            magnitudes: normalized,
            durationSeconds: durationSeconds
        )
    }
}
