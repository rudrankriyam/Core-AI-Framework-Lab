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
        #expect(removal.profiles == [.cpuOnly])
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
            await workspace.inspect(url: slowURL)
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
        #expect(removal.profiles.isEmpty)
        #expect(removal.assetCount == 1)
    }
}
