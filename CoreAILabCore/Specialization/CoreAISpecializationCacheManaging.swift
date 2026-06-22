import Foundation

protocol CoreAISpecializationCacheManaging: Sendable {
    func removeCachedEntry(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) async throws
    func removeCachedEntries(at url: URL) async throws
}

extension CoreAISpecializationService: CoreAISpecializationCacheManaging {}
