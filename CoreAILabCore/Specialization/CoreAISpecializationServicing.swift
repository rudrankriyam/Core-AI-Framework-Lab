import Foundation

protocol CoreAISpecializationServicing: Sendable {
    func reset() async
    func isCached(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) async throws -> Bool
    func specialize(
        at url: URL,
        configuration: CoreAISpecializationConfiguration,
        cachePolicy: CoreAICachePolicyChoice
    ) async throws -> CoreAISpecializationResult
    func removeCachedEntry(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) async throws
    func removeCachedEntries(at url: URL) async throws
}
