import Foundation
import Testing
@testable import CoreAILab

@MainActor
struct AppleAudioWorkspaceModelTests {
    @Test
    func ctcDecoderCollapsesRepeatsBlanksAndWordSeparators() throws {
        let tokens = [0, 8, 8, 0, 7, 7, 1, 1, 0, 8, 7]
        let emissions = makeEmissions(tokens: tokens)

        let transcript = try Wav2Vec2CTCDecoder.decode(
            emissions: emissions,
            shape: [1, tokens.count, Wav2Vec2CTCDecoder.labels.count]
        )

        #expect(transcript == "HI HI")
    }

    @Test
    func transcriptionUsesTheSelectedAudio() async {
        let engine = AppleAudioTranscriberStub(transcript: "HELLO")
        let workspace = AppleAudioWorkspaceModel(engine: engine)
        await workspace.loadModel(from: URL(filePath: "/tmp/wav2vec2.aimodel"))
        workspace.selectAudio(URL(filePath: "/tmp/speech.wav"))

        workspace.startTranscription()
        await waitForTranscription(workspace)

        #expect(await engine.audioURLs == [URL(filePath: "/tmp/speech.wav")])
        #expect(workspace.result?.transcript == "HELLO")
        #expect(!workspace.isShowingError)
    }

    @Test
    func failedReplacementPreservesTheRunnableAudioModel() async {
        let engine = AppleAudioTranscriberStub(transcript: "STILL READY")
        let workspace = AppleAudioWorkspaceModel(engine: engine)
        await workspace.loadModel(from: URL(filePath: "/tmp/valid-wav2vec2.aimodel"))
        await workspace.loadModel(from: URL(filePath: "/tmp/invalid-wav2vec2.aimodel"))
        #expect(workspace.isShowingError)
        workspace.selectAudio(URL(filePath: "/tmp/speech.wav"))

        workspace.startTranscription()
        await waitForTranscription(workspace)

        #expect(workspace.modelName == "valid-wav2vec2.aimodel")
        #expect(workspace.result?.transcript == "STILL READY")
        #expect(!workspace.isShowingError)
    }

    @Test
    func cancellationDiscardsALateTranscript() async throws {
        let engine = AppleAudioTranscriberStub(
            transcript: "TOO LATE",
            transcriptionDelay: .milliseconds(100)
        )
        let workspace = AppleAudioWorkspaceModel(engine: engine)
        await workspace.loadModel(from: URL(filePath: "/tmp/wav2vec2.aimodel"))
        workspace.selectAudio(URL(filePath: "/tmp/speech.wav"))

        workspace.startTranscription()
        try await Task.sleep(for: .milliseconds(10))
        workspace.cancelTranscription()
        await waitForTranscription(workspace)

        #expect(workspace.result == nil)
        #expect(workspace.statusMessage == "Transcription canceled.")
    }

    @Test
    func audioLoaderResamplesToSixteenKilohertzMono() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "core-ai-audio-(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let sourceSamples = (0..<2_400).map { index in
            Float(sin(Double(index) * 0.05) * 0.2)
        }
        try ChatterboxWaveFile.write(samples: sourceSamples, to: url)

        let converted = try AppleAudioSampleLoader.loadMono16k(
            from: url,
            maximumDurationSeconds: 5
        )

        #expect(abs(converted.values.count - 1_600) <= 2)
        #expect(abs(converted.durationSeconds - 0.1) < 0.001)
    }

    private func makeEmissions(tokens: [Int]) -> [Float] {
        tokens.flatMap { selected in
            (0..<Wav2Vec2CTCDecoder.labels.count).map { token in
                token == selected ? 1 : 0
            }
        }
    }

    private func waitForTranscription(_ workspace: AppleAudioWorkspaceModel) async {
        while workspace.isTranscribing {
            await Task.yield()
        }
    }
}

private actor AppleAudioTranscriberStub: AppleAudioTranscribing {
    private let transcript: String
    private let transcriptionDelay: Duration?
    private(set) var audioURLs: [URL] = []
    private var isLoaded = false

    init(transcript: String, transcriptionDelay: Duration? = nil) {
        self.transcript = transcript
        self.transcriptionDelay = transcriptionDelay
    }

    func loadModel(at url: URL) throws -> AppleAudioModelInfo {
        if url.lastPathComponent.contains("invalid") {
            throw AppleAudioTranscriberStubError.invalidModel
        }
        isLoaded = true
        return AppleAudioModelInfo(
            sampleCount: 80_000,
            sampleRate: 16_000,
            scalarTypeName: "float16"
        )
    }

    func transcribe(audioAt url: URL) async throws -> AppleAudioTranscriptionResult {
        guard isLoaded else { throw AppleAudioError.modelNotLoaded }
        audioURLs.append(url)
        if let transcriptionDelay {
            try await Task.sleep(for: transcriptionDelay)
        }
        return AppleAudioTranscriptionResult(
            transcript: transcript,
            audioDurationSeconds: 1,
            inferenceDurationSeconds: 0.2
        )
    }
}

private enum AppleAudioTranscriberStubError: LocalizedError {
    case invalidModel

    var errorDescription: String? {
        "The replacement Wav2Vec2 model is invalid."
    }
}
