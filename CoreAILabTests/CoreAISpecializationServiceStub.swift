import Foundation
@testable import CoreAILab

actor CoreAISpecializationServiceStub: CoreAISpecializationServicing {
    private var cachedProfiles: Set<CoreAISpecializationProfile>
    private var removedProfiles: [CoreAISpecializationProfile] = []
    private var removedAssetCount = 0

    init(cachedProfiles: Set<CoreAISpecializationProfile> = []) {
        self.cachedProfiles = cachedProfiles
    }

    func reset() {}

    func isCached(
        at url: URL,
        profile: CoreAISpecializationProfile
    ) -> Bool {
        cachedProfiles.contains(profile)
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
