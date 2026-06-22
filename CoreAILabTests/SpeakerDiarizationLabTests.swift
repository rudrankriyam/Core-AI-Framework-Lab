import AVFoundation
import Foundation
import Testing
#if os(macOS)
import AVKit
#endif
@testable import CoreAILab

struct SpeakerDiarizationLabTests {
    @Test
    func analysisLayoutUsesAContentDrivenBreakpoint() {
        let breakpoint = SpeakerDiarizationAnalysisLayout.minimumSideBySideWidth

        #expect(
            SpeakerDiarizationAnalysisLayout(contentWidth: breakpoint - 1) == .stacked
        )
        #expect(
            SpeakerDiarizationAnalysisLayout(contentWidth: breakpoint) == .sideBySide
        )
    }

    @Test
    func stubDiarizationCoversTheImportedDuration() {
        let result = SpeakerDiarizationStubEngine.makeResult(durationSeconds: 65)

        #expect(result.engineName == SpeakerDiarizationStubEngine.name)
        #expect(result.speakerNames == ["Speaker 1", "Speaker 2"])
        #expect(result.turns.first?.startTime == 0)
        #expect(result.turns.last?.endTime == 65)
        #expect(result.turns.allSatisfy { $0.duration > 0 })
        #expect(result.turn(at: 0)?.id == result.turns.first?.id)
        #expect(result.turn(at: 65)?.id == result.turns.last?.id)
    }

    @Test
    func stubDiarizationNeverExtendsPastShortMedia() {
        let duration = 0.25
        let result = SpeakerDiarizationStubEngine.makeResult(
            durationSeconds: duration
        )

        #expect(result.turns.count == 1)
        #expect(result.turns.first?.startTime == 0)
        #expect(result.turns.last?.endTime == duration)
        #expect(result.turns.allSatisfy { $0.endTime <= duration })
        #expect(
            SpeakerDiarizationStubEngine.makeResult(durationSeconds: 0).turns.isEmpty
        )
    }

    @Test
    func timeFormatterPreservesPositiveSubsecondDurations() {
        #expect(SpeakerDiarizationTimeFormatter.format(0) == "0:00")
        #expect(SpeakerDiarizationTimeFormatter.format(0.25) == "0:00.25")
        #expect(SpeakerDiarizationTimeFormatter.format(0.001) == "0:00.01")
        #expect(SpeakerDiarizationTimeFormatter.format(1.9) == "0:01")
    }

    @Test
    func mediaAnalyzerBuildsNormalizedWaveformBuckets() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "core-ai-diarization-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        try writeSineWave(to: url)

        let analysis = try await SpeakerDiarizationMediaAnalyzer.analyze(
            url: url,
            bucketCount: 16
        )

        #expect(analysis.summary.fileName == url.lastPathComponent)
        #expect(analysis.summary.kind == .audio)
        #expect(analysis.summary.channelCount == 1)
        #expect(abs(analysis.summary.durationSeconds - 0.25) < 0.01)
        #expect(analysis.waveform.magnitudes.count == 16)
        #expect((analysis.waveform.magnitudes.max() ?? 0) <= 1)
        #expect((analysis.waveform.magnitudes.max() ?? 0) > 0)
    }

    @Test
    @MainActor
    func playbackWatcherOwnsTheCompletePlaybackLifecycle() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "core-ai-watcher-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSineWave(to: url)

        let watcher = SpeakerDiarizationWatcherModel()
        let summary = SpeakerDiarizationMediaSummary(
            fileName: url.lastPathComponent,
            kind: .audio,
            durationSeconds: 0.25,
            sampleRate: 16_000,
            channelCount: 1
        )

        watcher.load(url: url, summary: summary)
        #expect(watcher.player != nil)
        #expect(watcher.currentTime == 0)
        #expect(!watcher.isPlaying)

        watcher.togglePlayback()
        #expect(watcher.isPlaying)

        watcher.togglePlayback()
        #expect(!watcher.isPlaying)

        watcher.currentTime = summary.durationSeconds
        watcher.togglePlayback()
        #expect(watcher.currentTime == 0)
        #expect(watcher.isPlaying)

        watcher.currentTime = 0.1
        watcher.restart()
        #expect(watcher.currentTime == 0)
        #expect(watcher.isPlaying)

        watcher.reset()
        #expect(watcher.player == nil)
        #expect(watcher.currentTime == 0)
        #expect(!watcher.isPlaying)

        watcher.load(url: nil, summary: nil)
        #expect(watcher.player == nil)
    }

#if os(macOS)
    @Test
    @MainActor
    func macOSVideoWatcherUsesThePublicPlayerView() {
        let player = AVPlayer()
        let playerView = SpeakerDiarizationMacVideoPlayer.makePlayerView(
            player: player
        )

        #expect(playerView.player === player)
        #expect(playerView.controlsStyle == .none)
        #expect(!playerView.updatesNowPlayingInfoCenter)
        #expect(!playerView.allowsVideoFrameAnalysis)
    }
#endif

    private func writeSineWave(to url: URL) throws {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let frameCount = 4_000
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        )
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = try #require(buffer.floatChannelData?[0])
        for frame in 0..<frameCount {
            channel[frame] = Float(sin(Double(frame) * 0.08) * 0.4)
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
