import Foundation

struct CoreAISpecializationResult: Sendable, Equatable {
    let configuration: CoreAISpecializationConfiguration
    let artifactDigest: CoreAIArtifactDigest
    let duration: Duration
    let loadedFromCache: Bool
    let functionNames: [String]
    let bookmarkData: Data
}
