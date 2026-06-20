import Foundation
import Observation

@MainActor
@Observable
final class CoreAIFunctionWorkbenchWorkspaceModel {
    let assetWorkspace: CoreAIAssetWorkspaceModel
    let deviceArchitectureName = CoreAIDiscoverySnapshot.current().deviceArchitectureName
    private(set) var contracts: [CoreAIFunctionContract] = []
    var selectedFunctionName: String? {
        didSet {
            guard selectedFunctionName != oldValue else { return }
            rebuildInputDrafts()
            runResult = nil
        }
    }
    private(set) var inputDrafts: [CoreAIFunctionInputDraft] = []
    private(set) var runResult: CoreAIFunctionRunResult?
    private(set) var contractLoadFailureMessage: String?
    private(set) var phase: CoreAIFunctionWorkbenchPhase = .idle

    @ObservationIgnored
    private let runtimeService: any CoreAIFunctionRuntimeServicing
    @ObservationIgnored
    private var contractOperationID = UUID()

    init(
        inspectionService: any CoreAIAssetInspecting = CoreAIAssetInspectionService(),
        runtimeService: any CoreAIFunctionRuntimeServicing = CoreAISpecializationService()
    ) {
        self.runtimeService = runtimeService
        assetWorkspace = CoreAIAssetWorkspaceModel(
            inspectionService: inspectionService,
            specializationService: runtimeService
        )
    }

    var selectedContract: CoreAIFunctionContract? {
        contracts.first { $0.name == selectedFunctionName }
    }

    var canRun: Bool {
        selectedContract?.isRunnable == true
            && !phase.isBusy
            && !assetWorkspace.phase.isBusy
            && inputDrafts.count == selectedContract?.inputs.count
    }

    func loadAsset(from url: URL) async {
        guard !phase.isBusy else { return }
        phase = .loadingAsset
        let didReplaceAsset = await assetWorkspace.inspect(url: url)
        if didReplaceAsset {
            clearRuntimeState()
        }
        phase = assetWorkspace.report == nil ? .idle : .ready
    }

    func specializationChanged(
        _ result: CoreAISpecializationResult?
    ) async {
        let operationID = UUID()
        contractOperationID = operationID
        guard assetWorkspace.specializationResult == result else { return }
        guard let result else {
            clearRuntimeState()
            if phase != .loadingAsset {
                phase = assetWorkspace.report == nil ? .idle : .ready
            }
            return
        }

        phase = .preparingContracts
        contractLoadFailureMessage = nil
        do {
            let refreshedContracts = try await runtimeService.functionContracts()
            guard isCurrentContractOperation(operationID, result: result) else { return }
            contracts = refreshedContracts
            selectedFunctionName = refreshedContracts.first?.name
            runResult = nil
            phase = .ready
        } catch {
            guard isCurrentContractOperation(operationID, result: result) else { return }
            contracts = []
            selectedFunctionName = nil
            contractLoadFailureMessage = error.localizedDescription
            phase = .ready
            assetWorkspace.presentImportError(error)
        }
    }

    func reloadContracts() async {
        await specializationChanged(assetWorkspace.specializationResult)
    }

    func runSelectedFunction() async {
        guard let selectedFunctionName, canRun else { return }
        phase = .running
        do {
            let plans = try inputDrafts.map { try $0.plan() }
            runResult = try await runtimeService.runFunction(
                named: selectedFunctionName,
                inputs: plans
            )
            phase = .ready
        } catch {
            phase = .ready
            assetWorkspace.presentImportError(error)
        }
    }

    func presentImportError(_ error: any Error) {
        assetWorkspace.presentImportError(error)
    }

    private func rebuildInputDrafts() {
        inputDrafts = selectedContract?.inputs.compactMap(CoreAIFunctionInputDraft.init) ?? []
    }

    private func clearRuntimeState() {
        contractOperationID = UUID()
        contracts = []
        selectedFunctionName = nil
        inputDrafts = []
        runResult = nil
        contractLoadFailureMessage = nil
    }

    private func isCurrentContractOperation(
        _ operationID: UUID,
        result: CoreAISpecializationResult
    ) -> Bool {
        !Task.isCancelled
            && contractOperationID == operationID
            && assetWorkspace.specializationResult == result
    }
}
