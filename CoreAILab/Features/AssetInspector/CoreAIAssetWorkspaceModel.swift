import Foundation
import Observation

@MainActor
@Observable
final class CoreAIAssetWorkspaceModel {
    private(set) var report: CoreAIModelAssetReport?
    private(set) var isInspecting = false
    private(set) var errorMessage: String?
    var isShowingError = false

    @ObservationIgnored
    private let inspectionService: any CoreAIAssetInspecting

    init(inspectionService: any CoreAIAssetInspecting = CoreAIAssetInspectionService()) {
        self.inspectionService = inspectionService
    }

    func inspect(url: URL) async {
        isInspecting = true
        defer { isInspecting = false }

        do {
            report = try await inspectionService.inspect(url: url)
            errorMessage = nil
            isShowingError = false
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }

    func presentImportError(_ error: any Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }
}
