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
    private(set) var exportStatusMessage: String?
    private(set) var exportedPackageURL: URL?
    var exportExpectFrequentReshapes = false

    @ObservationIgnored
    private let runtimeService: any CoreAIFunctionRuntimeServicing
    @ObservationIgnored
    private let integrationExporter: CoreAIIntegrationExporter
    @ObservationIgnored
    private var contractOperationID = UUID()
    @ObservationIgnored
    private var benchmarkTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    @ObservationIgnored
    private var exportOperationID = UUID()

    init(
        inspectionService: any CoreAIAssetInspecting = CoreAIAssetInspectionService(),
        runtimeService: any CoreAIFunctionRuntimeServicing = CoreAISpecializationService(),
        integrationExporter: CoreAIIntegrationExporter = CoreAIIntegrationExporter()
    ) {
        self.runtimeService = runtimeService
        self.integrationExporter = integrationExporter
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
            && exportTask == nil
            && inputDrafts.count == selectedContract?.inputs.count
    }

    var canBenchmark: Bool {
        canRun
    }

    var canExportIntegration: Bool {
        assetWorkspace.report?.isValid == true
            && !contracts.isEmpty
            && !phase.isBusy
            && !assetWorkspace.phase.isBusy
            && exportTask == nil
    }

    var isExportingIntegration: Bool {
        exportTask != nil
    }

    func loadAsset(from url: URL) async {
        guard !phase.isBusy, exportTask == nil else { return }
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

    func startIntegrationExport(to destinationParentURL: URL) {
        guard canExportIntegration,
              let report = assetWorkspace.report else { return }
        let contracts = contracts
        let profile = assetWorkspace.selectedProfile
        let operationID = UUID()
        exportOperationID = operationID
        exportStatusMessage = "Exporting model, manifest, and Swift runtime…"
        exportedPackageURL = nil
        exportTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if exportOperationID == operationID {
                    exportTask = nil
                }
            }
            do {
                let result = try await integrationExporter.export(
                    report: report,
                    contracts: contracts,
                    specializationProfile: profile,
                    expectFrequentReshapes: exportExpectFrequentReshapes,
                    destinationParentURL: destinationParentURL
                )
                guard exportOperationID == operationID else { return }
                exportedPackageURL = result.packageURL
                exportStatusMessage = "Created \(result.packageURL.lastPathComponent)."
            } catch is CancellationError {
                exportStatusMessage = "Integration export canceled."
            } catch {
                exportStatusMessage = nil
                assetWorkspace.presentImportError(error)
            }
        }
    }

    func cancelIntegrationExport() {
        exportTask?.cancel()
    }

    private func rebuildInputDrafts() {
        inputDrafts = selectedContract?.inputs.compactMap(CoreAIFunctionInputDraft.init) ?? []
    }

    private func clearRuntimeState(resetBenchmarkHistory: Bool = true) {
        exportOperationID = UUID()
        exportTask?.cancel()
        exportTask = nil
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
        exportStatusMessage = nil
        exportedPackageURL = nil
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
