import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class ChatterboxWorkspaceModel {
    var prompt = "Oh, that's hilarious! [chuckle] This voice is running entirely on your Mac with Core AI."
    var modelState = ChatterboxModelState.notLoaded
    var generatedResult: ChatterboxGenerationResult?
    var isWorking = false
    var isPlaying = false
    var statusMessage = "Preparing Core AI"
    var presentedError: ChatterboxPresentedError?

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
        statusMessage = "Specializing four models for the Apple GPU"
        modelState = .preparing

        do {
            modelState = .ready(try await engine.prepareBundledModels())
        } catch {
            modelState = .failed(error.localizedDescription)
            present(error)
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
        statusMessage = "Generating speech entirely with Core AI"
        generatedResult = nil

        do {
            let result = try await engine.synthesize(
                ChatterboxGenerationRequest(text: prompt)
            )
            generatedResult = result
            play(result)
        } catch {
            present(error)
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
            present(error)
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    private func present(_ error: Error) {
        presentedError = ChatterboxPresentedError(
            message: error.localizedDescription
        )
    }
}
