import Foundation
import Testing
@testable import CoreAILab

@MainActor
struct AppleLanguageWorkspaceModelTests {
    @Test
    func qwenBundleGeneratesWithTheSubmittedLimit() async {
        let engine = AppleLanguageGeneratorStub(response: "On-device AI keeps data local.")
        let workspace = AppleLanguageWorkspaceModel(example: .qwen3_0_6B, engine: engine)
        await workspace.loadModel(from: URL(filePath: "/tmp/qwen3_0_6b_4bit_dynamic"))
        workspace.prompt = "  Why local?  "
        workspace.maximumResponseTokens = 64

        workspace.startGeneration()
        await waitForGeneration(workspace)

        #expect(await engine.requests == [.init(prompt: "Why local?", maximumTokens: 64)])
        #expect(workspace.response == "On-device AI keeps data local.")
        #expect(!workspace.isShowingError)
    }

    @Test
    func failedReplacementPreservesTheRunnableLanguageModel() async {
        let engine = AppleLanguageGeneratorStub(response: "Still ready")
        let workspace = AppleLanguageWorkspaceModel(example: .qwen3_0_6B, engine: engine)
        await workspace.loadModel(from: URL(filePath: "/tmp/valid-qwen"))
        await workspace.loadModel(from: URL(filePath: "/tmp/invalid-qwen"))
        #expect(workspace.isShowingError)

        workspace.startGeneration()
        await waitForGeneration(workspace)

        #expect(workspace.modelName == "valid-qwen")
        #expect(workspace.response == "Still ready")
    }

    @Test
    func newSessionClearsTheResponseAndResetsTheEngine() async {
        let engine = AppleLanguageGeneratorStub(response: "First response")
        let workspace = AppleLanguageWorkspaceModel(example: .qwen3_0_6B, engine: engine)
        await workspace.loadModel(from: URL(filePath: "/tmp/qwen"))
        workspace.startGeneration()
        await waitForGeneration(workspace)
        #expect(!workspace.response.isEmpty)

        await workspace.resetSession()

        #expect(workspace.response.isEmpty)
        #expect(await engine.resetCount == 1)
    }

    @Test
    func cancellationDiscardsALateResponse() async throws {
        let engine = AppleLanguageGeneratorStub(
            response: "This must not be committed",
            responseDelay: .milliseconds(100)
        )
        let workspace = AppleLanguageWorkspaceModel(example: .qwen3_0_6B, engine: engine)
        await workspace.loadModel(from: URL(filePath: "/tmp/qwen"))

        workspace.startGeneration()
        try await Task.sleep(for: .milliseconds(10))
        workspace.cancelGeneration()
        await waitForGeneration(workspace)

        #expect(workspace.response.isEmpty)
        #expect(workspace.statusMessage == "Generation canceled.")
    }

    private func waitForGeneration(_ workspace: AppleLanguageWorkspaceModel) async {
        while workspace.isGenerating {
            await Task.yield()
        }
    }
}

private actor AppleLanguageGeneratorStub: AppleLanguageGenerating {
    struct Request: Equatable, Sendable {
        let prompt: String
        let maximumTokens: Int
    }

    private let response: String
    private let responseDelay: Duration?
    private(set) var requests: [Request] = []
    private(set) var resetCount = 0
    private var isLoaded = false

    init(response: String, responseDelay: Duration? = nil) {
        self.response = response
        self.responseDelay = responseDelay
    }

    func loadModel(at url: URL) throws {
        if url.lastPathComponent.contains("invalid") {
            throw AppleLanguageGeneratorStubError.invalidModel
        }
        isLoaded = true
    }

    func respond(to prompt: String, maximumResponseTokens: Int) async throws -> String {
        guard isLoaded else { throw AppleLanguageModelError.modelNotLoaded }
        requests.append(.init(prompt: prompt, maximumTokens: maximumResponseTokens))
        if let responseDelay {
            try await Task.sleep(for: responseDelay)
        }
        return response
    }

    func resetSession() async throws {
        guard isLoaded else { throw AppleLanguageModelError.modelNotLoaded }
        resetCount += 1
    }
}

private enum AppleLanguageGeneratorStubError: LocalizedError {
    case invalidModel

    var errorDescription: String? {
        "The replacement language-model bundle is invalid."
    }
}
