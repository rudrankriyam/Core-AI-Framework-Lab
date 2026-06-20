import Foundation
import Observation

@MainActor
@Observable
final class CoreAIAssetWorkspaceModel {
    private(set) var report: CoreAIModelAssetReport?
    private(set) var phase: CoreAIAssetWorkspacePhase = .idle
    private(set) var errorMessage: String?
    private(set) var cacheStatus: CoreAICacheEntryStatus = .unchecked
    private(set) var specializationResult: CoreAISpecializationResult?
    var selectedProfile: CoreAISpecializationProfile = .automatic {
        didSet {
            guard selectedProfile != oldValue else { return }
            cacheStatus = .unchecked
            specializationResult = nil
        }
    }
    var selectedCachePolicy: CoreAICachePolicyChoice = .standard
    var pendingCacheRemoval: CoreAICacheRemovalScope?
    var isConfirmingCacheRemoval = false
    var isShowingError = false

    @ObservationIgnored
    private let inspectionService: any CoreAIAssetInspecting
    @ObservationIgnored
    private let specializationService: any CoreAISpecializationServicing
    @ObservationIgnored
    private var operationID = UUID()

    init(
        inspectionService: any CoreAIAssetInspecting = CoreAIAssetInspectionService(),
        specializationService: any CoreAISpecializationServicing = CoreAISpecializationService()
    ) {
        self.inspectionService = inspectionService
        self.specializationService = specializationService
    }

    var isInspecting: Bool {
        phase == .inspecting
    }

    var canSpecialize: Bool {
        report != nil && selectedProfile.isAvailable && !phase.isBusy
    }

    var cacheRemovalTitle: String {
        pendingCacheRemoval?.title ?? "Remove Cached Specialization"
    }

    var cacheRemovalMessage: String {
        pendingCacheRemoval?.confirmationMessage ?? "The model will need to be specialized again."
    }

    func inspect(url: URL) async {
        let operationID = begin(.inspecting)

        do {
            let inspectedReport = try await inspectionService.inspect(url: url)
            guard self.operationID == operationID else { return }
            await specializationService.reset()
            guard self.operationID == operationID else { return }
            report = inspectedReport
            cacheStatus = .unchecked
            specializationResult = nil
            clearError()
            phase = .checkingCache
            await refreshCacheStatus(expectedOperationID: operationID)
        } catch {
            guard self.operationID == operationID else { return }
            phase = report == nil ? .idle : .ready
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }

    func refreshCacheStatus() async {
        guard report != nil, !phase.isBusy else { return }
        let operationID = begin(.checkingCache)
        await refreshCacheStatus(expectedOperationID: operationID)
    }

    func specialize() async {
        guard let report, canSpecialize else { return }
        let operationID = begin(.specializing)
        do {
            let result = try await specializationService.specialize(
                at: report.url,
                profile: selectedProfile,
                cachePolicy: selectedCachePolicy
            )
            guard self.operationID == operationID else { return }
            specializationResult = result
            cacheStatus = .cached
            clearError()
            phase = .ready
        } catch {
            present(error, operationID: operationID)
        }
    }

    func prepareCacheRemoval(_ scope: CoreAICacheRemovalScope) {
        guard report != nil, !phase.isBusy else { return }
        pendingCacheRemoval = scope
        isConfirmingCacheRemoval = true
    }

    func removePreparedCacheEntry() async {
        guard let report, let pendingCacheRemoval, !phase.isBusy else { return }
        isConfirmingCacheRemoval = false
        let operationID = begin(.removingCache)
        do {
            switch pendingCacheRemoval {
            case .selectedProfile:
                try await specializationService.removeCachedEntry(
                    at: report.url,
                    profile: selectedProfile
                )
            case .allProfilesForAsset:
                try await specializationService.removeCachedEntries(at: report.url)
            }
            guard self.operationID == operationID else { return }
            specializationResult = nil
            cacheStatus = .notCached
            self.pendingCacheRemoval = nil
            clearError()
            phase = .ready
        } catch {
            present(error, operationID: operationID)
        }
    }

    func presentImportError(_ error: any Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    private func refreshCacheStatus(expectedOperationID: UUID) async {
        guard let report else { return }
        cacheStatus = .checking
        do {
            let isCached = try await specializationService.isCached(
                at: report.url,
                profile: selectedProfile
            )
            guard operationID == expectedOperationID else { return }
            cacheStatus = isCached ? .cached : .notCached
            clearError()
            phase = .ready
        } catch {
            cacheStatus = .unchecked
            present(error, operationID: expectedOperationID)
        }
    }

    private func begin(_ phase: CoreAIAssetWorkspacePhase) -> UUID {
        let operationID = UUID()
        self.operationID = operationID
        self.phase = phase
        return operationID
    }

    private func present(_ error: any Error, operationID: UUID) {
        guard self.operationID == operationID else { return }
        phase = report == nil ? .idle : .ready
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    private func clearError() {
        errorMessage = nil
        isShowingError = false
    }
}
