import Foundation
import Testing
@testable import CoreAILab

struct AppleDiffusionIntegrationTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["COREAI_DIFFUSION_BUNDLE_PATH"] != nil,
            "Requires COREAI_DIFFUSION_BUNDLE_PATH."
        )
    )
    func exportedPipelineGeneratesThroughAppleRuntime() async throws {
        let bundlePath = try #require(
            ProcessInfo.processInfo.environment["COREAI_DIFFUSION_BUNDLE_PATH"]
        )

        let engine = AppleDiffusionPipelineEngine()
        let info = try await engine.loadPipeline(at: URL(filePath: bundlePath))
        let result = try await engine.generate(
            AppleDiffusionRequest(
                prompt: "a red circle on a white background",
                negativePrompt: "",
                seed: 1,
                stepCount: 1,
                guidanceScale: 7.5
            )
        )

        #expect(result.image.width == info.width)
        #expect(result.image.height == info.height)
    }
}
