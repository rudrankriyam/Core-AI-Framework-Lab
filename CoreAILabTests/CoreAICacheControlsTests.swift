import Foundation
import Testing
@testable import CoreAILab

@MainActor
struct CoreAICacheControlsTests {
    @Test
    func selectedProfileDrivesLookupSpecializationAndRemoval() async {
        let assetURL = URL(filePath: "/tmp/fixture.aimodel")
        let cache = CoreAISpecializationServiceStub(cachedProfiles: [.automatic])
        let workspace = CoreAIAssetWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            specializationService: cache
        )

        await workspace.inspect(url: assetURL)
        #expect(workspace.cacheStatus == .cached)

        workspace.selectedProfile = .cpuOnly
        #expect(workspace.cacheStatus == .unchecked)
        await workspace.refreshCacheStatus()
        #expect(workspace.cacheStatus == .notCached)

        await workspace.specialize()
        #expect(workspace.cacheStatus == .cached)
        #expect(workspace.specializationResult?.functionNames == ["main"])

        workspace.prepareCacheRemoval(.selectedProfile)
        await workspace.removePreparedCacheEntry()
        let removal = await cache.removalSnapshot()
        #expect(
            removal.configurations == [
                CoreAISpecializationConfiguration(profile: .cpuOnly)
            ]
        )
        #expect(removal.profileURLs == [assetURL])
        #expect(removal.assetCount == 0)
        #expect(workspace.cacheStatus == .notCached)
    }

    @Test
    func newestInspectionWinsWhenImportsOverlap() async throws {
        let workspace = CoreAIAssetWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            specializationService: CoreAISpecializationServiceStub()
        )
        let slowURL = URL(filePath: "/tmp/slow.aimodel")
        let fastURL = URL(filePath: "/tmp/fast.aimodel")

        let slowTask = Task {
            _ = await workspace.inspect(url: slowURL)
        }
        try await Task.sleep(for: .milliseconds(10))
        await workspace.inspect(url: fastURL)
        await slowTask.value

        #expect(workspace.report?.url == fastURL)
        #expect(workspace.phase == .ready)
    }

    @Test
    func assetWideRemovalUsesTheAssetScope() async {
        let assetURL = URL(filePath: "/tmp/fixture.aimodel")
        let cache = CoreAISpecializationServiceStub(
            cachedProfiles: [.automatic, .cpuOnly]
        )
        let workspace = CoreAIAssetWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            specializationService: cache
        )

        await workspace.inspect(url: assetURL)
        workspace.prepareCacheRemoval(.allProfilesForAsset)
        await workspace.removePreparedCacheEntry()

        let removal = await cache.removalSnapshot()
        #expect(removal.configurations.isEmpty)
        #expect(removal.assetCount == 1)
        #expect(removal.assetURLs == [assetURL])
    }

    @Test
    func importingAnotherAssetCancelsPreparedRemoval() async {
        let originalURL = URL(filePath: "/tmp/original.aimodel")
        let cache = CoreAISpecializationServiceStub()
        let workspace = CoreAIAssetWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            specializationService: cache
        )
        await workspace.inspect(url: originalURL)
        workspace.prepareCacheRemoval(.allProfilesForAsset)
        #expect(workspace.isConfirmingCacheRemoval)

        await workspace.inspect(url: URL(filePath: "/tmp/replacement.aimodel"))
        #expect(!workspace.isConfirmingCacheRemoval)
        await workspace.removePreparedCacheEntry()

        let removal = await cache.removalSnapshot()
        #expect(removal.assetCount == 0)
        #expect(removal.assetURLs.isEmpty)
    }

    @Test
    func changingProfileCancelsPreparedRemoval() async {
        let cache = CoreAISpecializationServiceStub()
        let workspace = CoreAIAssetWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            specializationService: cache
        )
        await workspace.inspect(url: URL(filePath: "/tmp/fixture.aimodel"))
        workspace.prepareCacheRemoval(.selectedProfile)
        #expect(workspace.isConfirmingCacheRemoval)

        workspace.selectedProfile = .cpuOnly
        #expect(!workspace.isConfirmingCacheRemoval)
        await workspace.removePreparedCacheEntry()

        let removal = await cache.removalSnapshot()
        #expect(removal.configurations.isEmpty)
        #expect(removal.profileURLs.isEmpty)
    }

    @Test
    func failedReplacementCannotLeaveASupersededCacheLookupChecking() async {
        let originalURL = URL(filePath: "/tmp/original.aimodel")
        let cache = CoreAISpecializationServiceStub(delayedCacheLookup: 2)
        let workspace = CoreAIAssetWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            specializationService: cache
        )
        await workspace.inspect(url: originalURL)

        let refresh = Task {
            await workspace.refreshCacheStatus()
        }
        while workspace.cacheStatus != .checking {
            await Task.yield()
        }
        await workspace.inspect(url: URL(filePath: "/tmp/invalid.aimodel"))
        await refresh.value

        #expect(workspace.report?.url == originalURL)
        #expect(workspace.phase == .ready)
        #expect(workspace.cacheStatus == .unchecked)
        #expect(workspace.isShowingError)
    }

    @Test
    func staleCacheFailureCannotOverwriteANewerSuccessfulInspection() async {
        let cache = CoreAISpecializationServiceStub(
            delayedCacheLookup: 2,
            failingCacheLookups: [2]
        )
        let workspace = CoreAIAssetWorkspaceModel(
            inspectionService: CoreAIDelayedAssetInspectorStub(),
            specializationService: cache
        )
        await workspace.inspect(url: URL(filePath: "/tmp/original.aimodel"))

        let staleRefresh = Task {
            await workspace.refreshCacheStatus()
        }
        while workspace.cacheStatus != .checking {
            await Task.yield()
        }
        let replacementURL = URL(filePath: "/tmp/replacement.aimodel")
        await workspace.inspect(url: replacementURL)
        await staleRefresh.value

        #expect(workspace.report?.url == replacementURL)
        #expect(workspace.phase == .ready)
        #expect(workspace.cacheStatus == .notCached)
        #expect(!workspace.isShowingError)
    }
}
