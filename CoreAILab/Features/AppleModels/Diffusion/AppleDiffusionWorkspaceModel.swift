import Foundation
import Observation

@MainActor
@Observable
final class AppleDiffusionWorkspaceModel {
    let example: AppleDiffusionExample
    let runCoordinator: CoreAIRunLifecycleCoordinator
    private(set) var modelName: String?
    private(set) var modelInfo: AppleDiffusionModelInfo?
    private(set) var result: AppleDiffusionResult?
    private(set) var statusMessage = "Import an Apple-exported diffusion resource bundle."
    private(set) var isLoadingModel = false
    private(set) var isGenerating = false
    private(set) var errorMessage: String?
    var prompt = "A tiny glass greenhouse glowing in a mossy forest, cinematic light"
    var negativePrompt = "blurry, low quality"
    var seed = 42
    var stepCount = 20
    var guidanceScale = 7.5
    var isShowingError = false

    @ObservationIgnored
    private let engine: any AppleDiffusionGenerating
    @ObservationIgnored
    private var generationTask: Task<Void, Never>?
    @ObservationIgnored
    private let runContext: CoreAIRuntimeRunContext

    init(
        example: AppleDiffusionExample,
        engine: any AppleDiffusionGenerating = AppleDiffusionPipelineEngine(),
        runContext: CoreAIRuntimeRunContext? = nil,
        runCoordinator: CoreAIRunLifecycleCoordinator? = nil
    ) {
        self.example = example
        self.engine = engine
        self.runContext = runContext ?? .workspaceDefault(
            experienceID: "apple-diffusion-\(example.rawValue)",
            title: example.title,
            modelIdentifier: example.rawValue
        )
        self.runCoordinator = runCoordinator ?? CoreAIRunLifecycleCoordinator()
    }

    var isBusy: Bool {
        isLoadingModel || isGenerating
    }

    var canGenerate: Bool {
        modelInfo != nil && !normalizedPrompt.isEmpty && !isBusy
    }

    func loadPipeline(from url: URL) async {
        guard !isBusy else { return }
        isLoadingModel = true
        statusMessage = "Loading \(url.lastPathComponent) and its pipeline components…"
        defer { isLoadingModel = false }

        do {
            try CoreAIRuntimeArtifactValidator.validate(
                url,
                for: .appleDiffusion,
                context: runContext
            )
            let loadedInfo = try await engine.loadPipeline(at: url)
            modelName = url.lastPathComponent
            runCoordinator.modelDidLoad(
                context: runContext,
                modelIdentity: url.lastPathComponent
            )
            modelInfo = loadedInfo
            stepCount = loadedInfo.defaultStepCount
            guidanceScale = Double(loadedInfo.defaultGuidanceScale)
            result = nil
            clearError()
            statusMessage = "\(loadedInfo.pipelineName) is ready at \(loadedInfo.width) × \(loadedInfo.height)."
        } catch {
            present(error)
        }
    }

    func startGeneration() {
        guard generationTask == nil, canGenerate else { return }
        let request = AppleDiffusionRequest(
            prompt: normalizedPrompt,
            negativePrompt: modelInfo?.supportsNegativePrompt == true
                ? negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                : "",
            seed: UInt32(clamping: seed),
            stepCount: stepCount,
            guidanceScale: Float(guidanceScale)
        )
        result = nil
        isGenerating = true
        statusMessage = "Generating locally with \(modelInfo?.pipelineName ?? example.title)…"
        let runToken = runCoordinator.start(
            context: runContext,
            modelIdentity: modelName ?? runContext.comparisonIdentity.modelIdentifier
        )
        let coordinator = runCoordinator
        generationTask = Task { [weak self, coordinator] in
            guard let self else {
                coordinator.cancel(runToken, summary: "Diffusion workspace closed.")
                return
            }
            await self.performGeneration(request, runToken: runToken)
        }
    }

    func cancelGeneration() {
        guard generationTask != nil else { return }
        statusMessage = "Canceling image generation…"
        generationTask?.cancel()
    }

    func presentImportError(_ error: any Error) {
        present(error)
    }

    private var normalizedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performGeneration(
        _ request: AppleDiffusionRequest,
        runToken: CoreAIRuntimeRunToken
    ) async {
        defer {
            generationTask = nil
            isGenerating = false
        }

        do {
            let generated = try await engine.generate(request)
            try Task.checkCancellation()
            result = generated
            clearError()
            statusMessage = "Generated on device in \(generated.durationSeconds.formatted(.number.precision(.fractionLength(2)))) seconds."
            runCoordinator.succeed(runToken, summary: statusMessage)
        } catch is CancellationError {
            result = nil
            statusMessage = "Image generation canceled."
            runCoordinator.cancel(runToken, summary: statusMessage)
        } catch {
            runCoordinator.fail(runToken, error: error)
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
