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
    private(set) var phase: CoreAIFunctionWorkbenchPhase = .idle

    @ObservationIgnored
    private let runtimeService: any CoreAIFunctionRuntimeServicing

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
        clearRuntimeState()
        await assetWorkspace.inspect(url: url)
        phase = assetWorkspace.report == nil ? .idle : .ready
    }

    func specializationChanged(
        _ result: CoreAISpecializationResult?
    ) async {
        guard result != nil else {
            clearRuntimeState()
            phase = assetWorkspace.report == nil ? .idle : .ready
            return
        }
        guard !phase.isBusy else { return }
        phase = .preparingContracts
        do {
            contracts = try await runtimeService.functionContracts()
            selectedFunctionName = contracts.first?.name
            runResult = nil
            phase = .ready
        } catch {
            phase = .ready
            assetWorkspace.presentImportError(error)
        }
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
        contracts = []
        selectedFunctionName = nil
        inputDrafts = []
        runResult = nil
    }
}
