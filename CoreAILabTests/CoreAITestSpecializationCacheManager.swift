import Foundation
@testable import CoreAILab

actor CoreAITestSpecializationCacheManager: CoreAISpecializationCacheManaging {
    private(set) var removedEntries: [(
        url: URL,
        configuration: CoreAISpecializationConfiguration
    )] = []
    private(set) var removedAssetURLs: [URL] = []
    private var shouldRejectRemovals = false
    private var removalDelay: Duration?

    func rejectRemovals() {
        shouldRejectRemovals = true
    }

    func delayRemovals(by duration: Duration) {
        removalDelay = duration
    }

    func removeCachedEntry(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) async throws {
        if let removalDelay {
            try await Task.sleep(for: removalDelay)
        }
        if shouldRejectRemovals {
            throw CocoaError(.fileWriteNoPermission)
        }
        removedEntries.append((url: url, configuration: configuration))
    }

    func removeCachedEntries(at url: URL) async throws {
        if let removalDelay {
            try await Task.sleep(for: removalDelay)
        }
        if shouldRejectRemovals {
            throw CocoaError(.fileWriteNoPermission)
        }
        removedAssetURLs.append(url)
    }
}
