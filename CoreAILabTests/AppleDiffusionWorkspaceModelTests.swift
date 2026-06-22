import CoreGraphics
import Foundation
import Testing
@testable import CoreAILab

@MainActor
struct AppleDiffusionWorkspaceModelTests {
    @Test
    func catalogModelsMapToTheirRunnablePipelines() {
        #expect(AppleDiffusionExample(shortName: "sd-1.5") == .stableDiffusion15)
        #expect(AppleDiffusionExample(shortName: "sd-2.1") == .stableDiffusion21)
        #expect(AppleDiffusionExample(shortName: "sd-3.5-medium") == .stableDiffusion35)
        #expect(AppleDiffusionExample(shortName: "flux2-klein-4b") == .flux2Klein4B)
        #expect(AppleDiffusionExample(shortName: "qwen3-0.6b") == nil)
    }

    @Test
    func selectedRecipeRejectsAMismatchedDiffusionFamilyBeforeLoading() async throws {
        let engine = try AppleDiffusionGeneratorStub(image: makeTestImage())
        let runContext = CoreAIRuntimeRunContext(
            experienceID: "apple-sd15-generation",
            experienceTitle: "Stable Diffusion 1.5",
            recipeIdentifier: "apple.coreai-models.sd-1.5",
            recipeRevision: "fixture-revision",
            recipeProvenance: .unverifiedIntent,
            comparisonIdentity: CoreAIRuntimeComparisonIdentity(
                experienceID: "apple-sd15-generation",
                modelIdentifier: "sd-1.5",
                displayName: "Stable Diffusion 1.5"
            )
        )
        let workspace = AppleDiffusionWorkspaceModel(
            example: .stableDiffusion15,
            engine: engine,
            runContext: runContext
        )

        await workspace.loadPipeline(
            from: URL(filePath: "/tmp/flux2-klein-4b-export")
        )

        #expect(workspace.modelName == nil)
        #expect(workspace.isShowingError)
        #expect(
            workspace.errorMessage
                == "This experience expects sd-1.5, but the imported artifact identifies as flux2-klein-4b."
        )
        #expect(await engine.loadAttempts == 0)
    }

    @Test
    func generationUsesNormalizedControls() async throws {
        let engine = try AppleDiffusionGeneratorStub(image: makeTestImage())
        let workspace = AppleDiffusionWorkspaceModel(
            example: .stableDiffusion15,
            engine: engine
        )
        await workspace.loadPipeline(from: URL(filePath: "/tmp/stable-diffusion"))
        workspace.prompt = "  a lighthouse in fog  "
        workspace.negativePrompt = "  blurry  "
        workspace.seed = 7
        workspace.stepCount = 12
        workspace.guidanceScale = 6.5

        workspace.startGeneration()
        await waitForGeneration(workspace)

        #expect(await engine.requests == [
            AppleDiffusionRequest(
                prompt: "a lighthouse in fog",
                negativePrompt: "blurry",
                seed: 7,
                stepCount: 12,
                guidanceScale: 6.5
            )
        ])
        #expect(workspace.result?.image.width == 4)
        #expect(workspace.statusMessage == "Generated on device in 0.25 seconds.")
        #expect(!workspace.isShowingError)
    }

    @Test
    func failedReplacementPreservesTheRunnablePipeline() async throws {
        let engine = try AppleDiffusionGeneratorStub(image: makeTestImage())
        let workspace = AppleDiffusionWorkspaceModel(example: .stableDiffusion21, engine: engine)
        await workspace.loadPipeline(from: URL(filePath: "/tmp/valid-pipeline"))
        await workspace.loadPipeline(from: URL(filePath: "/tmp/invalid-pipeline"))
        #expect(workspace.isShowingError)

        workspace.startGeneration()
        await waitForGeneration(workspace)

        #expect(workspace.modelName == "valid-pipeline")
        #expect(workspace.result != nil)
        #expect(!workspace.isShowingError)
    }

    @Test
    func fluxUsesBundleDefaultsAndOmitsUnsupportedNegativePrompt() async throws {
        let info = AppleDiffusionModelInfo(
            pipelineName: "FLUX.2",
            width: 512,
            height: 512,
            supportsImageToImage: false,
            defaultStepCount: 4,
            defaultGuidanceScale: 1,
            supportsNegativePrompt: false
        )
        let engine = try AppleDiffusionGeneratorStub(
            image: makeTestImage(),
            modelInfo: info
        )
        let workspace = AppleDiffusionWorkspaceModel(example: .flux2Klein4B, engine: engine)
        workspace.negativePrompt = "this must not reach FLUX"

        await workspace.loadPipeline(from: URL(filePath: "/tmp/flux2"))
        #expect(workspace.stepCount == 4)
        #expect(workspace.guidanceScale == 1)

        workspace.startGeneration()
        await waitForGeneration(workspace)

        #expect(await engine.requests.first?.negativePrompt == "")
    }

    @Test
    func cancellationDiscardsALateImage() async throws {
        let engine = try AppleDiffusionGeneratorStub(
            image: makeTestImage(),
            generationDelay: .milliseconds(100)
        )
        let workspace = AppleDiffusionWorkspaceModel(example: .stableDiffusion35, engine: engine)
        await workspace.loadPipeline(from: URL(filePath: "/tmp/sd3"))

        workspace.startGeneration()
        try await Task.sleep(for: .milliseconds(10))
        workspace.cancelGeneration()
        await waitForGeneration(workspace)

        #expect(workspace.result == nil)
        #expect(workspace.statusMessage == "Image generation canceled.")
    }

    private func waitForGeneration(_ workspace: AppleDiffusionWorkspaceModel) async {
        while workspace.isGenerating {
            await Task.yield()
        }
    }

    private func makeTestImage() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: 4,
                height: 3,
                bitsPerComponent: 8,
                bytesPerRow: 16,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        return try #require(context.makeImage())
    }
}

private actor AppleDiffusionGeneratorStub: AppleDiffusionGenerating {
    private let image: CGImage
    private let modelInfo: AppleDiffusionModelInfo
    private let generationDelay: Duration?
    private(set) var requests: [AppleDiffusionRequest] = []
    private(set) var loadAttempts = 0
    private var isLoaded = false

    init(
        image: CGImage,
        modelInfo: AppleDiffusionModelInfo? = nil,
        generationDelay: Duration? = nil
    ) {
        self.image = image
        self.modelInfo = modelInfo ?? AppleDiffusionModelInfo(
            pipelineName: "Test Diffusion",
            width: image.width,
            height: image.height,
            supportsImageToImage: false,
            defaultStepCount: 20,
            defaultGuidanceScale: 7.5,
            supportsNegativePrompt: true
        )
        self.generationDelay = generationDelay
    }

    func loadPipeline(at url: URL) throws -> AppleDiffusionModelInfo {
        loadAttempts += 1
        if url.lastPathComponent.contains("invalid") {
            throw AppleDiffusionGeneratorStubError.invalidPipeline
        }
        isLoaded = true
        return modelInfo
    }

    func generate(_ request: AppleDiffusionRequest) async throws -> AppleDiffusionResult {
        guard isLoaded else { throw AppleDiffusionError.pipelineNotLoaded }
        requests.append(request)
        if let generationDelay {
            try await Task.sleep(for: generationDelay)
        }
        return AppleDiffusionResult(image: image, durationSeconds: 0.25)
    }
}

private enum AppleDiffusionGeneratorStubError: LocalizedError {
    case invalidPipeline

    var errorDescription: String? {
        "The replacement diffusion pipeline is invalid."
    }
}
