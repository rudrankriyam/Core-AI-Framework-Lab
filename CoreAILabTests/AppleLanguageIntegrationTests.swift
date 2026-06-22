import Foundation
import Testing
@testable import CoreAILab

struct AppleLanguageIntegrationTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["COREAI_QWEN_BUNDLE_PATH"] != nil,
            "Requires COREAI_QWEN_BUNDLE_PATH."
        )
    )
    func exportedQwenGeneratesThroughAppleRuntime() async throws {
        let bundlePath = try #require(
            ProcessInfo.processInfo.environment["COREAI_QWEN_BUNDLE_PATH"]
        )

        let engine = AppleLanguageModelEngine()
        try await engine.loadModel(at: URL(filePath: bundlePath))
        let response = try await engine.respond(
            to: "Reply with the word hello.",
            maximumResponseTokens: 4
        )

        #expect(!response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
