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
    private let generationDelay: Duration?
    private(set) var requests: [AppleDiffusionRequest] = []
    private var isLoaded = false

    init(image: CGImage, generationDelay: Duration? = nil) {
        self.image = image
        self.generationDelay = generationDelay
    }

    func loadPipeline(at url: URL) throws -> AppleDiffusionModelInfo {
        if url.lastPathComponent.contains("invalid") {
            throw AppleDiffusionGeneratorStubError.invalidPipeline
        }
        isLoaded = true
        return AppleDiffusionModelInfo(
            pipelineName: "Test Diffusion",
            width: image.width,
            height: image.height,
            supportsImageToImage: false
        )
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
