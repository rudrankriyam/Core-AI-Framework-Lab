import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class ChatterboxWorkspaceModel {
    var prompt = "Oh, that's hilarious! [chuckle] This voice was generated locally with Core AI."
    var modelState = ChatterboxModelState.notLoaded
    var generatedResult: ChatterboxGenerationResult?
    var isWorking = false
    var isPlaying = false
    var statusMessage = "Preparing Core AI…"
    var presentedError: ChatterboxPresentedError?
    private(set) var recipeManifest: CoreAIRecipeManifest?

    @ObservationIgnored
    private let engine: ChatterboxCoreAIEngine
    @ObservationIgnored
    private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored
    private var playbackTask: Task<Void, Never>?
    @ObservationIgnored
    private var hasPrepared = false

    init(engine: ChatterboxCoreAIEngine = ChatterboxCoreAIEngine()) {
        self.engine = engine
    }

    var inspection: ChatterboxModelInspection? {
        guard case .ready(let inspection) = modelState else {
            return nil
        }
        return inspection
    }

    var isShowingError: Bool {
        get { presentedError != nil }
        set {
            if !newValue {
                presentedError = nil
            }
        }
    }

    var canGenerate: Bool {
        guard let inspection else {
            return false
        }
        return inspection.contractValidation.isComplete
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isWorking
    }

    func prepare() async {
        guard !hasPrepared else {
            return
        }
        hasPrepared = true
        isWorking = true
        modelState = .preparing

        do {
            let manifest = try await engine.bundledRecipeManifest()
            recipeManifest = manifest
            let targetName = manifest.defaultTarget?.displayName ?? "selected target"
            statusMessage = "Specializing \(manifest.pipeline.stages.count) models for \(targetName)…"
            let inspection = try await engine.prepareBundledModels()
            modelState = .ready(inspection)
            statusMessage = "Ready to generate speech."
        } catch {
            recipeManifest = nil
            modelState = .failed(error.localizedDescription)
            statusMessage = "Core AI preparation failed."
            present(error, title: "Couldn't Prepare Chatterbox")
        }
        isWorking = false
    }

    func generate() {
        Task(priority: .userInitiated) {
            await synthesize()
        }
    }

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else if let generatedResult {
            play(generatedResult)
        }
    }

    private func synthesize() async {
        stopPlayback()
        isWorking = true
        statusMessage = "Generating speech with Core AI…"
        generatedResult = nil

        do {
            let result = try await engine.synthesize(
                ChatterboxGenerationRequest(text: prompt)
            )
            generatedResult = result
            statusMessage = "Generated \(result.audioDuration.formatted(.number.precision(.fractionLength(1)))) seconds of speech in \(result.elapsedTime.formatted(.number.precision(.fractionLength(1)))) seconds."
            play(result)
        } catch {
            statusMessage = "Speech generation failed."
            present(error, title: "Couldn't Generate Speech")
        }
        isWorking = false
    }

    private func play(_ result: ChatterboxGenerationResult) {
        do {
            let player = try AVAudioPlayer(contentsOf: result.audioURL)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            isPlaying = true

            playbackTask?.cancel()
            playbackTask = Task { [weak self] in
                try? await Task.sleep(
                    for: .seconds(result.audioDuration + 0.1)
                )
                guard !Task.isCancelled else {
                    return
                }
                self?.isPlaying = false
            }
        } catch {
            isPlaying = false
            statusMessage = "Speech is ready, but playback couldn't start."
            present(error, title: "Couldn't Play Speech")
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    private func present(_ error: Error, title: String) {
        presentedError = ChatterboxPresentedError(
            title: title,
            message: error.localizedDescription
        )
    }
}
