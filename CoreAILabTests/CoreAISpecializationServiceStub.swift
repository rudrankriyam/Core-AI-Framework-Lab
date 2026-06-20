import Foundation
@testable import CoreAILab

actor CoreAISpecializationServiceStub: CoreAISpecializationServicing {
    private var cachedProfiles: Set<CoreAISpecializationProfile>
    private var removedProfiles: [CoreAISpecializationProfile] = []
    private var removedAssetCount = 0
    private var cacheLookupCount = 0
    private let delayedCacheLookup: Int?
    private let failingCacheLookups: Set<Int>

    init(
        cachedProfiles: Set<CoreAISpecializationProfile> = [],
        delayedCacheLookup: Int? = nil,
        failingCacheLookups: Set<Int> = []
    ) {
        self.cachedProfiles = cachedProfiles
        self.delayedCacheLookup = delayedCacheLookup
        self.failingCacheLookups = failingCacheLookups
    }

    func reset() {}

    func isCached(
        at url: URL,
        profile: CoreAISpecializationProfile
    ) async throws -> Bool {
        cacheLookupCount += 1
        let lookup = cacheLookupCount
        if delayedCacheLookup == lookup {
            try await Task.sleep(for: .milliseconds(100))
        }
        if failingCacheLookups.contains(lookup) {
            throw CocoaError(.fileReadUnknown)
        }
        return cachedProfiles.contains(profile)
    }

    func specialize(
        at url: URL,
        profile: CoreAISpecializationProfile,
        cachePolicy: CoreAICachePolicyChoice
    ) -> CoreAISpecializationResult {
        cachedProfiles.insert(profile)
        return CoreAISpecializationResult(
            duration: .milliseconds(25),
            loadedFromCache: false,
            functionNames: ["main"],
            bookmarkData: Data([0xCA, 0xFE])
        )
    }

    func removeCachedEntry(
        at url: URL,
        profile: CoreAISpecializationProfile
    ) {
        cachedProfiles.remove(profile)
        removedProfiles.append(profile)
    }

    func removeCachedEntries(at url: URL) {
        cachedProfiles.removeAll()
        removedAssetCount += 1
    }

    func removalSnapshot() -> (profiles: [CoreAISpecializationProfile], assetCount: Int) {
        (removedProfiles, removedAssetCount)
    }
}
