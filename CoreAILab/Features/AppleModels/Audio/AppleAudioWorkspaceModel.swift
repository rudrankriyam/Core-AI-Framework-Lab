import Foundation
import Observation

@MainActor
@Observable
final class AppleAudioWorkspaceModel {
    let example: AppleAudioExample
    private(set) var modelName: String?
    private(set) var modelInfo: AppleAudioModelInfo?
    private(set) var audioName: String?
    private(set) var result: AppleAudioTranscriptionResult?
    private(set) var statusMessage = "Import Apple's exported Wav2Vec2 model and an audio clip."
    private(set) var isLoadingModel = false
    private(set) var isTranscribing = false
    private(set) var errorMessage: String?
    var isShowingError = false

    @ObservationIgnored
    private let engine: any AppleAudioTranscribing
    @ObservationIgnored
    private var audioURL: URL?
    @ObservationIgnored
    private var transcriptionTask: Task<Void, Never>?

    init(
        example: AppleAudioExample = .wav2Vec2,
        engine: any AppleAudioTranscribing = AppleWav2Vec2Engine()
    ) {
        self.example = example
        self.engine = engine
    }

    var isBusy: Bool {
        isLoadingModel || isTranscribing
    }

    var canTranscribe: Bool {
        modelInfo != nil && audioURL != nil && !isBusy
    }

    func loadModel(from url: URL) async {
        guard !isBusy else { return }
        isLoadingModel = true
        statusMessage = "Specializing \(url.lastPathComponent)…"
        defer { isLoadingModel = false }

        do {
            let info = try await engine.loadModel(at: url)
            modelName = url.lastPathComponent
            modelInfo = info
            result = nil
            clearError()
            let seconds = Double(info.sampleCount) / info.sampleRate
            statusMessage = "Wav2Vec2 is ready for up to \(seconds.formatted()) seconds of audio."
        } catch {
            present(error)
        }
    }

    func selectAudio(_ url: URL) {
        guard !isBusy else { return }
        audioURL = url
        audioName = url.lastPathComponent
        result = nil
        clearError()
        statusMessage = "Ready to transcribe \(url.lastPathComponent)."
    }

    func startTranscription() {
        guard transcriptionTask == nil, canTranscribe, let audioURL else { return }
        result = nil
        isTranscribing = true
        statusMessage = "Decoding, resampling, and transcribing locally…"
        transcriptionTask = Task { [weak self] in
            await self?.performTranscription(audioURL)
        }
    }

    func cancelTranscription() {
        guard transcriptionTask != nil else { return }
        statusMessage = "Canceling transcription…"
        transcriptionTask?.cancel()
    }

    func presentImportError(_ error: any Error) {
        present(error)
    }

    private func performTranscription(_ audioURL: URL) async {
        defer {
            transcriptionTask = nil
            isTranscribing = false
        }

        do {
            let transcription = try await engine.transcribe(audioAt: audioURL)
            try Task.checkCancellation()
            result = transcription
            clearError()
            statusMessage = "Transcribed on device in \(transcription.inferenceDurationSeconds.formatted(.number.precision(.fractionLength(2)))) seconds."
        } catch is CancellationError {
            result = nil
            statusMessage = "Transcription canceled."
        } catch {
            present(error)
        }
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        statusMessage = error.localizedDescription
        isShowingError = true
    }

    private func clearError() {
        errorMessage = nil
        isShowingError = false
    }
}
