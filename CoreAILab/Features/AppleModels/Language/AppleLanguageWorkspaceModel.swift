import Foundation
import Observation

@MainActor
@Observable
final class AppleLanguageWorkspaceModel {
    let example: AppleLanguageExample
    private(set) var modelName: String?
    private(set) var response = ""
    private(set) var statusMessage = "Import an Apple-exported Qwen resource bundle."
    private(set) var isLoadingModel = false
    private(set) var isGenerating = false
    private(set) var isResettingSession = false
    private(set) var errorMessage: String?
    var prompt = "Explain why on-device AI is useful in three sentences."
    var maximumResponseTokens = 128
    var isShowingError = false

    @ObservationIgnored
    private let engine: any AppleLanguageGenerating
    @ObservationIgnored
    private var generationTask: Task<Void, Never>?

    init(
        example: AppleLanguageExample,
        engine: any AppleLanguageGenerating = AppleLanguageModelEngine()
    ) {
        self.example = example
        self.engine = engine
    }

    var isBusy: Bool {
        isLoadingModel || isGenerating || isResettingSession
    }

    var canGenerate: Bool {
        modelName != nil && !normalizedPrompt.isEmpty && !isBusy
    }

    func loadModel(from url: URL) async {
        guard !isBusy else { return }
        isLoadingModel = true
        statusMessage = "Loading \(url.lastPathComponent) and its tokenizer…"
        defer { isLoadingModel = false }

        do {
            try await engine.loadModel(at: url)
            modelName = url.lastPathComponent
            response = ""
            clearError()
            statusMessage = "Qwen is ready for a new session."
        } catch {
            present(error)
        }
    }

    func startGeneration() {
        guard generationTask == nil, canGenerate else { return }
        let submittedPrompt = normalizedPrompt
        let submittedMaximumTokens = maximumResponseTokens
        response = ""
        isGenerating = true
        statusMessage = "Generating locally with \(example.title)…"
        generationTask = Task { [weak self] in
            await self?.performGeneration(
                prompt: submittedPrompt,
                maximumResponseTokens: submittedMaximumTokens
            )
        }
    }

    func cancelGeneration() {
        guard generationTask != nil else { return }
        statusMessage = "Canceling generation…"
        generationTask?.cancel()
    }

    func resetSession() async {
        guard modelName != nil, !isBusy else { return }
        isResettingSession = true
        defer { isResettingSession = false }

        do {
            try await engine.resetSession()
            response = ""
            clearError()
            statusMessage = "Started a fresh Qwen session."
        } catch {
            present(error)
        }
    }

    func presentImportError(_ error: any Error) {
        present(error)
    }

    private var normalizedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performGeneration(
        prompt: String,
        maximumResponseTokens: Int
    ) async {
        defer {
            generationTask = nil
            isGenerating = false
        }

        do {
            let generated = try await engine.respond(
                to: prompt,
                maximumResponseTokens: maximumResponseTokens
            )
            try Task.checkCancellation()
            response = generated
            clearError()
            statusMessage = "Generated \(generated.count) characters on device."
        } catch is CancellationError {
            response = ""
            statusMessage = "Generation canceled."
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
