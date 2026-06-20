import Foundation
import Testing
@testable import CoreAILab

struct AppleLanguageIntegrationTests {
    @Test
    func exportedQwenGeneratesThroughAppleRuntime() async throws {
        guard let bundlePath = ProcessInfo.processInfo.environment["COREAI_QWEN_BUNDLE_PATH"] else {
            return
        }

        let engine = AppleLanguageModelEngine()
        try await engine.loadModel(at: URL(filePath: bundlePath))
        let response = try await engine.respond(
            to: "Reply with the word hello.",
            maximumResponseTokens: 4
        )

        #expect(!response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
