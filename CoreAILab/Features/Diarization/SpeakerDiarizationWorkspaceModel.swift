import Foundation
import Observation

@MainActor
@Observable
final class SpeakerDiarizationWorkspaceModel {
    private(set) var mediaURL: URL?
    private(set) var mediaSummary: SpeakerDiarizationMediaSummary?
    private(set) var waveform: SpeakerDiarizationWaveform?
    private(set) var modelInfo: SpeakerDiarizationModelInfo?
    private(set) var result: SpeakerDiarizationResult?
    private(set) var isAnalyzingMedia = false
    private(set) var isLoadingModel = false
    private(set) var isRunningDiarization = false
    private(set) var errorMessage: String?
    var isShowingError = false
    private(set) var statusMessage = "Preparing the bundled CAM++ model…"

    @ObservationIgnored
    private let engine: any SpeakerDiarizationServicing
    @ObservationIgnored
    private var analysisTask: Task<Void, Never>?
    @ObservationIgnored
    private var diarizationTask: Task<Void, Never>?
    @ObservationIgnored
    private var analysisGeneration = 0

    init(
        engine: any SpeakerDiarizationServicing = SpeakerDiarizationEngine()
    ) {
        self.engine = engine
    }

    var mediaName: String {
        mediaSummary?.fileName ?? "Not selected"
    }

    var modelName: String {
        modelInfo?.assetName ?? "Not loaded"
    }

    var canRunDiarization: Bool {
        modelInfo != nil && mediaURL != nil && waveform != nil && !isBusy
    }

    var isBusy: Bool {
        isAnalyzingMedia || isLoadingModel || isRunningDiarization
    }

    func prepareBundledModel(in bundle: Bundle = .main) async {
        guard modelInfo == nil else { return }
        do {
            let url = try SpeakerDiarizationBundledModel.url(in: bundle)
            await loadModel(from: url)
        } catch {
            present(error)
        }
    }

    func loadModel(from url: URL) async {
        guard !isLoadingModel, !isRunningDiarization else { return }
        isLoadingModel = true
        statusMessage = "Specializing \(url.lastPathComponent)…"
        defer { isLoadingModel = false }

        do {
            let candidate = try await engine.loadModel(at: url)
            try Task.checkCancellation()
            modelInfo = candidate
            result = nil
            clearError()
            statusMessage = mediaURL == nil
                ? "CAM++ is ready. Choose media or run diarization."
                : "Media and CAM++ are ready for batch diarization."
        } catch is CancellationError {
            statusMessage = "Model import canceled."
        } catch {
            present(error)
        }
    }

    func selectMedia(_ url: URL) {
        analysisTask?.cancel()
        diarizationTask?.cancel()
        diarizationTask = nil
        analysisGeneration += 1
        let generation = analysisGeneration
        mediaURL = nil
        mediaSummary = nil
        waveform = nil
        result = nil
        isRunningDiarization = false
        isAnalyzingMedia = true
        clearError()
        statusMessage = "Reading media and preparing waveform buckets…"
        analysisTask = Task { [weak self] in
            await self?.analyzeMedia(at: url, generation: generation)
        }
    }

    func startDiarization() {
        guard diarizationTask == nil, canRunDiarization, let mediaURL else {
            return
        }
        let generation = analysisGeneration
        result = nil
        isRunningDiarization = true
        clearError()
        statusMessage = "Decoding, segmenting, embedding, and clustering locally…"
        diarizationTask = Task { [weak self] in
            await self?.performDiarization(mediaURL: mediaURL, generation: generation)
        }
    }

    func cancelWork() {
        analysisTask?.cancel()
        diarizationTask?.cancel()
    }

    func presentImportError(_ error: any Error) {
        present(error)
    }

    private func analyzeMedia(at url: URL, generation: Int) async {
        defer {
            if generation == analysisGeneration {
                analysisTask = nil
                isAnalyzingMedia = false
            }
        }

        do {
            let analysis = try await SpeakerDiarizationMediaAnalyzer.analyze(url: url)
            guard !Task.isCancelled, generation == analysisGeneration else {
                return
            }
            mediaURL = url
            mediaSummary = analysis.summary
            waveform = analysis.waveform
            clearError()
            statusMessage = modelInfo == nil
                ? "Media is ready. Choose a compatible CAM++ model to diarize it."
                : "Media and CAM++ are ready for batch diarization."
        } catch is CancellationError {
        } catch {
            guard generation == analysisGeneration else {
                return
            }
            present(error)
        }
    }

    private func performDiarization(mediaURL: URL, generation: Int) async {
        defer {
            if generation == analysisGeneration {
                diarizationTask = nil
                isRunningDiarization = false
            }
        }

        do {
            let candidate = try await engine.diarize(mediaAt: mediaURL)
            guard !Task.isCancelled, generation == analysisGeneration else {
                return
            }
            result = candidate
            clearError()
            if candidate.turns.isEmpty {
                statusMessage = "Finished without detecting speech above the energy threshold."
            } else {
                statusMessage = "Finished \(candidate.turns.count.formatted()) anonymous speaker turns."
            }
        } catch is CancellationError {
        } catch {
            guard generation == analysisGeneration else {
                return
            }
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
