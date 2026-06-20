import Foundation

protocol AppleLanguageGenerating: Sendable {
    func loadModel(at url: URL) async throws
    func respond(to prompt: String, maximumResponseTokens: Int) async throws -> String
    func resetSession() async throws
}
