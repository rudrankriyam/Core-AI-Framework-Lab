import Foundation

protocol CoreAIArtifactDigesting: Sendable {
    func digest(at url: URL) async throws -> CoreAIArtifactDigest
}
