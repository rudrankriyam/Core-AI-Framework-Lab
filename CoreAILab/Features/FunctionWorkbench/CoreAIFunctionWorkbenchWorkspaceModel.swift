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
    var benchmarkConfiguration = CoreAIFunctionBenchmarkConfiguration()
    private(set) var benchmarkHistory: [CoreAIFunctionBenchmarkReport] = []
    private(set) var benchmarkStatusMessage: String?
    private(set) var contractLoadFailureMessage: String?
    private(set) var phase: CoreAIFunctionWorkbenchPhase = .idle

    @ObservationIgnored
    private let runtimeService: any CoreAIFunctionRuntimeServicing
    @ObservationIgnored
    private var contractOperationID = UUID()
    @ObservationIgnored
    private var benchmarkTask: Task<Void, Never>?

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

    var canBenchmark: Bool {
        canRun
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
            clearRuntimeState(resetBenchmarkHistory: false)
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

    func startBenchmark() {
        guard let selectedFunctionName,
              let asset = assetWorkspace.report,
              let specialization = assetWorkspace.specializationResult,
              canBenchmark else {
            return
        }

        let plans: [CoreAIFunctionInputPlan]
        do {
            try benchmarkConfiguration.validate()
            plans = try inputDrafts.map { try $0.plan() }
        } catch {
            assetWorkspace.presentImportError(error)
            return
        }

        benchmarkStatusMessage = nil
        phase = .benchmarking
        let configuration = benchmarkConfiguration
        benchmarkTask = Task { [weak self] in
            guard let self else { return }
            await self.performBenchmark(
                functionName: selectedFunctionName,
                assetName: asset.url.lastPathComponent,
                specialization: specialization,
                plans: plans,
                configuration: configuration
            )
        }
    }

    func stopBenchmarkAfterCurrentInference() {
        guard phase == .benchmarking else { return }
        benchmarkStatusMessage = "Stopping after the current Core AI inference finishes…"
        benchmarkTask?.cancel()
    }

    func cancelBenchmark() {
        benchmarkTask?.cancel()
    }

    func clearBenchmarkHistory() {
        guard phase != .benchmarking else { return }
        benchmarkHistory = []
        benchmarkStatusMessage = nil
    }

    func presentImportError(_ error: any Error) {
        assetWorkspace.presentImportError(error)
    }

    private func rebuildInputDrafts() {
        inputDrafts = selectedContract?.inputs.compactMap(CoreAIFunctionInputDraft.init) ?? []
    }

    private func clearRuntimeState(resetBenchmarkHistory: Bool = true) {
        benchmarkTask?.cancel()
        benchmarkTask = nil
        contractOperationID = UUID()
        contracts = []
        selectedFunctionName = nil
        inputDrafts = []
        runResult = nil
        if resetBenchmarkHistory {
            benchmarkHistory = []
        }
        benchmarkStatusMessage = nil
        contractLoadFailureMessage = nil
    }

    private func performBenchmark(
        functionName: String,
        assetName: String,
        specialization: CoreAISpecializationResult,
        plans: [CoreAIFunctionInputPlan],
        configuration: CoreAIFunctionBenchmarkConfiguration
    ) async {
        defer {
            benchmarkTask = nil
            if phase == .benchmarking {
                phase = .ready
            }
        }

        do {
            let result = try await runtimeService.benchmarkFunction(
                named: functionName,
                inputs: plans,
                configuration: configuration
            )
            guard assetWorkspace.specializationResult == specialization else { return }
            benchmarkHistory.insert(
                CoreAIFunctionBenchmarkReport(
                    assetName: assetName,
                    specializationConfiguration: specialization.configuration,
                    specializationDuration: specialization.duration,
                    loadedFromCache: specialization.loadedFromCache,
                    inputPlans: plans,
                    result: result
                ),
                at: 0
            )
            benchmarkStatusMessage = result.stoppedEarly
                ? "Stopped after \(result.trials.count) measured runs; completed evidence was retained."
                : nil
        } catch is CancellationError {
            benchmarkStatusMessage = "Benchmark stopped before a measured trial completed."
        } catch {
            assetWorkspace.presentImportError(error)
        }
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
