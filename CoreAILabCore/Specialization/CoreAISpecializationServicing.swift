import Foundation

protocol CoreAISpecializationServicing: Sendable {
    func reset() async
    func isCached(at url: URL, profile: CoreAISpecializationProfile) async throws -> Bool
    func specialize(
        at url: URL,
        profile: CoreAISpecializationProfile,
        cachePolicy: CoreAICachePolicyChoice
    ) async throws -> CoreAISpecializationResult
    func removeCachedEntry(at url: URL, profile: CoreAISpecializationProfile) async throws
    func removeCachedEntries(at url: URL) async throws
}
