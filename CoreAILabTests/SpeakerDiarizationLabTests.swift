import AVFoundation
import CoreAI
import Foundation
import Testing
#if os(macOS)
import AVKit
#endif
@testable import CoreAILab

struct SpeakerDiarizationLabTests {
    @Test
    @MainActor
    func bundledModelLoadsWhileMediaAnalysisIsAlreadyRunning() async {
        let service = SpeakerDiarizationServiceFake()
        let workspace = SpeakerDiarizationWorkspaceModel(engine: service)
        let missingMediaURL = FileManager.default.temporaryDirectory.appending(
            path: "diarization-race-\(UUID().uuidString).wav"
        )

        workspace.selectMedia(missingMediaURL)
        #expect(workspace.isAnalyzingMedia)

        await workspace.prepareBundledModel()

        #expect(
            workspace.modelInfo?.assetName
                == SpeakerDiarizationBundledModel.assetFilename
        )
        let loadCount = await service.loadCount
        #expect(loadCount == 1)
        workspace.cancelWork()
    }

    @Test
    func bundledCAMPlusHasPinnedLicenseProvenanceAndContract() async throws {
        let modelURL = try SpeakerDiarizationBundledModel.url()
        let asset = try AIModelAsset(contentsOf: modelURL)
        let provenanceURL = modelURL
            .deletingLastPathComponent()
            .appending(path: "MODEL_PROVENANCE.json")
        let provenanceData = try Data(contentsOf: provenanceURL)
        let provenance = try #require(String(data: provenanceData, encoding: .utf8))

        #expect(asset.metadata.license == "Apache-2.0")
        #expect(
            asset.metadata.description.contains(
                "e4b6ede7ce16997aff4ae69fbca1f0175e2afede"
            )
        )
        #expect(
            provenance.contains(
                "3388cf5fd3493c9ac9c69851d8e7a8badcfb4f3dc631020c4961371646d5ada8"
            )
        )
        #expect(
            provenance.contains(
                "dc27de457b9ed883592be59e25dd3d296d034ab92359eaf1a92840aa81f1c04b"
            )
        )

        let engine = SpeakerDiarizationEngine()
        let info = try await engine.loadModel(at: modelURL)
        #expect(info.frameCount == 600)
        #expect(info.featureBinCount == 80)
        #expect(info.embeddingDimension == 192)
        #expect(info.scalarTypeName == "float16")
    }

    @Test
    func energySegmentationFindsSeparatedSpeechAndRejectsSilence() {
        let sampleRate = 1_000
        var samples = Array(repeating: Float.zero, count: 5 * sampleRate)
        fillSpeech(in: 1_000..<2_000, samples: &samples)
        fillSpeech(in: 3_000..<4_000, samples: &samples)

        let segmenter = SpeakerDiarizationEnergySegmenter()
        let regions = segmenter.regions(
            in: SpeakerDiarizationAudio(samples: samples, sampleRate: sampleRate)
        )

        #expect(regions.count == 2)
        #expect(regions[0].sampleRange.contains(1_000))
        #expect(regions[0].sampleRange.contains(1_999))
        #expect(regions[1].sampleRange.contains(3_000))
        #expect(regions[1].sampleRange.contains(3_999))
        #expect(
            segmenter.regions(
                in: SpeakerDiarizationAudio(
                    samples: Array(repeating: 0, count: sampleRate),
                    sampleRate: sampleRate
                )
            ).isEmpty
        )
    }

    @Test
    func analysisWindowsUseSixSecondContextAndRepeatShortRegions() throws {
        let sampleRate = 16_000
        let samples = (0..<(10 * sampleRate)).map(Float.init)
        let builder = SpeakerDiarizationWindowBuilder()
        let windows = builder.windows(
            for: [SpeakerDiarizationSpeechRegion(sampleRange: 0..<samples.count)],
            sampleRate: sampleRate
        )

        #expect(windows.map(\.timelineSampleRange.count) == [48_000, 48_000, 48_000, 16_000])
        #expect(
            windows.allSatisfy {
                $0.featureSampleRange.count
                    == SpeakerDiarizationCAMPPlusFeatureExtractor.sampleCount
            }
        )

        let shortWindow = SpeakerDiarizationAnalysisWindow(
            timelineSampleRange: 0..<3,
            featureSampleRange: 0..<3
        )
        let repeated = try builder.modelSamples(
            for: shortWindow,
            audio: SpeakerDiarizationAudio(samples: [1, 2, 3], sampleRate: sampleRate),
            sampleCount: 8
        )
        #expect(repeated == [1, 2, 3, 1, 2, 3, 1, 2])
    }

    @Test
    func cosineClusteringReusesOnlySimilarSpeakerCentroids() throws {
        var clusterer = SpeakerDiarizationSpeakerClusterer(similarityThreshold: 0.65)

        let first = try clusterer.assign(embedding: [1, 0, 0])
        let same = try clusterer.assign(embedding: [0.99, 0.1, 0])
        let different = try clusterer.assign(embedding: [0, 1, 0])

        #expect(first.speakerIndex == 0)
        #expect(first.similarity == nil)
        #expect(same.speakerIndex == 0)
        #expect((same.similarity ?? 0) > 0.99)
        #expect(different.speakerIndex == 1)
        #expect(different.similarity == nil)
        #expect(clusterer.clusterCount == 2)
    }

    @Test
    func swiftFilterbankMatchesPinnedTorchaudioFixture() throws {
        let expected = try readFloat32Fixture(
            at: CoreAITestFixtures.diarizationFeatureURL()
        )
        let actual = try SpeakerDiarizationCAMPPlusFeatureExtractor.extract(
            samples: deterministicFeatureWaveform()
        ).values

        #expect(actual.count == 600 * 80)
        #expect(expected.count == actual.count)
        let differences = zip(actual, expected).map { abs($0 - $1) }
        #expect((differences.max() ?? .infinity) < 0.001)
        #expect(differences.reduce(0, +) / Float(differences.count) < 0.000_05)
    }

    @Test
    func realPipelineCombinesSegmentationEmbeddingAndClustering() async throws {
        let sampleRate = 16_000
        var samples = Array(repeating: Float.zero, count: 5 * sampleRate)
        fillSpeech(in: 8_000..<24_000, samples: &samples)
        fillSpeech(in: 48_000..<64_000, samples: &samples)
        let provider = SpeakerEmbeddingProviderFake(
            embeddings: [[1, 0, 0], [0, 1, 0]]
        )
        let engine = SpeakerDiarizationEngine(embeddingProvider: provider)

        _ = try await engine.loadModel(at: URL(filePath: "/tmp/CAMPPlus.aimodel"))
        let result = try await engine.diarize(
            audio: SpeakerDiarizationAudio(samples: samples, sampleRate: sampleRate)
        )

        #expect(result.engineName == SpeakerDiarizationEngine.name)
        #expect(result.speakerNames == ["Speaker 1", "Speaker 2"])
        #expect(result.turns.count == 2)
        #expect(result.turns.allSatisfy { $0.duration > 0 })
        #expect(result.evidence?.speechRegionCount == 2)
        #expect(result.evidence?.analysisWindowCount == 2)
        let embeddingCallCount = await provider.embeddingCallCount
        #expect(embeddingCallCount == 2)
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
    func audioDecoderProducesTheCAMPlusInputFormat() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "core-ai-diarization-decode-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSineWave(to: url)

        let audio = try await SpeakerDiarizationAudioDecoder.decode(url: url)

        #expect(audio.sampleRate == 16_000)
        #expect((3_900...4_100).contains(audio.samples.count))
        #expect(audio.samples.allSatisfy { $0.isFinite })
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

    private func fillSpeech(in range: Range<Int>, samples: inout [Float]) {
        for index in range {
            samples[index] = index.isMultiple(of: 2) ? 0.4 : -0.4
        }
    }

    private func deterministicFeatureWaveform() -> [Float] {
        (0..<SpeakerDiarizationCAMPPlusFeatureExtractor.sampleCount).map { index in
            Float((index % 97) - 48) / 256
                + Float((index % 53) - 26) / 512
        }
    }

    private func readFloat32Fixture(at url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        #expect(data.count.isMultiple(of: MemoryLayout<UInt32>.stride))
        return data.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: MemoryLayout<UInt32>.stride).map {
                let bits = UInt32(
                    littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self)
                )
                return Float(bitPattern: bits)
            }
        }
    }
}

private actor SpeakerDiarizationServiceFake: SpeakerDiarizationServicing {
    private(set) var loadCount = 0

    func loadModel(at url: URL) async throws -> SpeakerDiarizationModelInfo {
        loadCount += 1
        return SpeakerDiarizationModelInfo(
            assetName: url.lastPathComponent,
            frameCount: SpeakerDiarizationCAMPPlusFeatureExtractor.frameCount,
            featureBinCount: SpeakerDiarizationCAMPPlusFeatureExtractor.binCount,
            embeddingDimension: 192,
            scalarTypeName: "float16"
        )
    }

    func diarize(mediaAt url: URL) async throws -> SpeakerDiarizationResult {
        SpeakerDiarizationResult(
            engineName: "Test",
            turns: [],
            generatedAt: .now
        )
    }
}

private actor SpeakerEmbeddingProviderFake: SpeakerDiarizationEmbeddingProviding {
    private let embeddings: [[Float]]
    private(set) var embeddingCallCount = 0

    init(embeddings: [[Float]]) {
        self.embeddings = embeddings
    }

    func loadModel(at url: URL) async throws -> SpeakerDiarizationModelInfo {
        SpeakerDiarizationModelInfo(
            assetName: url.lastPathComponent,
            frameCount: SpeakerDiarizationCAMPPlusFeatureExtractor.frameCount,
            featureBinCount: SpeakerDiarizationCAMPPlusFeatureExtractor.binCount,
            embeddingDimension: embeddings.first?.count ?? 0,
            scalarTypeName: "float16"
        )
    }

    func embedding(for features: SpeakerDiarizationFeatures) async throws -> [Float] {
        guard embeddingCallCount < embeddings.count else {
            throw SpeakerDiarizationError.invalidEmbedding("fake embedding queue is empty")
        }
        defer { embeddingCallCount += 1 }
        return embeddings[embeddingCallCount]
    }
}
