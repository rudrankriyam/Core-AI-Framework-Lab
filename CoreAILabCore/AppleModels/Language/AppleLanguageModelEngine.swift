import CoreAILanguageModels
import Foundation
import FoundationModels

actor AppleLanguageModelEngine: AppleLanguageGenerating {
    private var model: CoreAILanguageModel?
    private var session: LanguageModelSession?

    func loadModel(at url: URL) async throws {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let loadedModel = try await CoreAILanguageModel(resourcesAt: url)
        model = loadedModel
        session = LanguageModelSession(model: loadedModel)
    }

    func respond(
        to prompt: String,
        maximumResponseTokens: Int
    ) async throws -> String {
        guard let session else {
            throw AppleLanguageModelError.modelNotLoaded
        }
        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(maximumResponseTokens: maximumResponseTokens)
        )
        return response.content
    }

    func resetSession() async throws {
        guard let model else {
            throw AppleLanguageModelError.modelNotLoaded
        }
        session = LanguageModelSession(model: model)
    }
}
