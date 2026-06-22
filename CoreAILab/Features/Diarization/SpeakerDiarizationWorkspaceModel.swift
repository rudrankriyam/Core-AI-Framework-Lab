import Foundation
import Observation

@MainActor
@Observable
final class SpeakerDiarizationWorkspaceModel {
    var mediaURL: URL?
    var mediaSummary: SpeakerDiarizationMediaSummary?
    var waveform: SpeakerDiarizationWaveform?
    var result: SpeakerDiarizationResult?
    var isAnalyzingMedia = false
    var isRunningStub = false
    var isShowingError = false
    var errorMessage: String?
    var statusMessage = "Choose audio or video to inspect speaker turns."

    @ObservationIgnored
    private var analysisTask: Task<Void, Never>?
    @ObservationIgnored
    private var analysisGeneration = 0

    var mediaName: String {
        mediaSummary?.fileName ?? "Not selected"
    }

    var canRunStub: Bool {
        waveform != nil && !isAnalyzingMedia && !isRunningStub
    }

    var isBusy: Bool {
        isAnalyzingMedia || isRunningStub
    }

    func selectMedia(_ url: URL) {
        analysisTask?.cancel()
        analysisGeneration += 1
        let generation = analysisGeneration
        mediaURL = nil
        mediaSummary = nil
        waveform = nil
        result = nil
        isAnalyzingMedia = true
        statusMessage = "Reading media and preparing waveform buckets..."
        analysisTask = Task { [weak self] in
            await self?.analyzeMedia(at: url, generation: generation)
        }
    }

    func runStubDiarization() {
        guard let mediaSummary, canRunStub else {
            return
        }

        isRunningStub = true
        result = SpeakerDiarizationStubEngine.makeResult(
            durationSeconds: mediaSummary.durationSeconds
        )
        statusMessage = "Generated anonymous speaker turns with the stub engine."
        isRunningStub = false
    }

    func presentImportError(_ error: any Error) {
        present(error)
    }

    private func analyzeMedia(at url: URL, generation: Int) async {
        do {
            let analysis = try await SpeakerDiarizationMediaAnalyzer.analyze(url: url)
            guard !Task.isCancelled, generation == analysisGeneration else {
                return
            }
            mediaURL = url
            mediaSummary = analysis.summary
            waveform = analysis.waveform
            statusMessage = "Ready to generate stub speaker turns."
        } catch is CancellationError {
        } catch {
            guard generation == analysisGeneration else {
                return
            }
            present(error)
            statusMessage = "Media import failed."
        }
        if generation == analysisGeneration {
            isAnalyzingMedia = false
        }
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }
}
