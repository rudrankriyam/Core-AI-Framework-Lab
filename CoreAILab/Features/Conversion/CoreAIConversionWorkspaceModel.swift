#if os(macOS)
import Foundation
import Observation

@MainActor
@Observable
final class CoreAIConversionWorkspaceModel {
    var selectedModelID: String? {
        didSet {
            guard selectedModelID != oldValue else { return }
            selectedPrecision = selectedModel?.shortName == "yolos-tiny" ? .float16 : nil
            environmentCheckID = UUID()
            environmentReport = nil
            if !phase.isBusy {
                phase = .idle
                statusMessage = "Verify the updated conversion environment."
            }
        }
    }
    var selectedPrecision: CoreAIConversionPrecision?
    var overwriteExistingArtifacts = false
    var uvExecutableURL: URL?
    var repositoryURL: URL?
    var outputDirectoryURL: URL
    var isShowingError = false

    private(set) var catalog: AppleCoreAIModelCatalogDocument?
    private(set) var catalogError: String?
    private(set) var environmentReport: CoreAIConversionEnvironmentReport?
    private(set) var isCheckingEnvironment = false
    private(set) var phase: CoreAIConversionPhase = .idle
    private(set) var statusMessage = "Choose a recipe repository and verify the environment."
    private(set) var logEntries: [CoreAIConversionLogEntry] = []
    private(set) var artifacts: [CoreAIConversionArtifact] = []
    private(set) var logURL: URL?
    private(set) var duration: Duration?
    private(set) var errorMessage: String?
    private(set) var processIdentifier: Int32?

    @ObservationIgnored
    private let environmentDoctor = CoreAIConversionEnvironmentDoctor()
    @ObservationIgnored
    private let processRunner = CoreAIConversionProcessRunner()
    @ObservationIgnored
    private var conversionTask: Task<Void, Never>?
    @ObservationIgnored
    private var environmentCheckID = UUID()

    init(initialModelID: String? = nil, bundle: Bundle = .main) {
        outputDirectoryURL = CoreAIConversionEnvironmentDetector.defaultOutputDirectory
        uvExecutableURL = CoreAIConversionEnvironmentDetector.findUVExecutable()
        repositoryURL = CoreAIConversionEnvironmentDetector.findRepository()

        do {
            let catalog = try AppleCoreAIModelCatalog.load(bundle: bundle)
            self.catalog = catalog
            let requestedModel = catalog.models.first { $0.id == initialModelID }
            let defaultModel = catalog.models.first { $0.shortName == "yolos-tiny" }
                ?? catalog.models.first
            selectedModelID = (requestedModel ?? defaultModel)?.id
            selectedPrecision = selectedModel?.shortName == "yolos-tiny" ? .float16 : nil
        } catch {
            catalogError = error.localizedDescription
        }
    }

    var models: [AppleCoreAIModel] {
        catalog?.models.sorted { first, second in
            if first.category != second.category {
                return first.category.rawValue < second.category.rawValue
            }
            if first.shortName != second.shortName {
                return first.shortName < second.shortName
            }
            return (first.variant ?? "") < (second.variant ?? "")
        } ?? []
    }

    var groups: [AppleCoreAIModelGroup] {
        AppleCoreAIModelCategory.allCases.compactMap { category in
            let entries = models.filter { $0.category == category }
            guard !entries.isEmpty else { return nil }
            return AppleCoreAIModelGroup(category: category, models: entries)
        }
    }

    var selectedModel: AppleCoreAIModel? {
        catalog?.models.first { $0.id == selectedModelID }
    }

    var selectedModelSubtitle: String {
        guard let selectedModel else { return "No recipe selected" }
        return [selectedModel.huggingFaceID, selectedModel.variant]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var supportsPrecisionSelection: Bool {
        !supportedPrecisions.isEmpty
    }

    var supportedPrecisions: [CoreAIConversionPrecision] {
        selectedModel?.supportedConversionPrecisions ?? []
    }

    var sourceRevision: String {
        catalog?.sourceRevision ?? "unknown"
    }

    var exportCommand: CoreAIConversionCommand? {
        guard let selectedModel, let uvExecutableURL, let repositoryURL else {
            return nil
        }
        return CoreAIConversionPlanner.exportCommand(
            model: selectedModel,
            uvExecutableURL: uvExecutableURL,
            repositoryURL: repositoryURL,
            outputDirectoryURL: outputDirectoryURL,
            precision: selectedPrecision,
            overwrite: overwriteExistingArtifacts
        )
    }

    var commandPreview: String {
        if let exportCommand {
            return exportCommand.displayString
        }
        guard let selectedModel else {
            return "Select a model recipe to create a conversion command."
        }
        return "\(selectedModel.labRecommendedExportCommand) --output-dir <output-folder>"
    }

    var canStartConversion: Bool {
        environmentReport?.canConvert == true
            && exportCommand != nil
            && phase.allowsStartingConversion
            && !isCheckingEnvironment
    }

    var canCancelConversion: Bool {
        conversionTask != nil && phase.isBusy
    }

    func refreshEnvironment() async {
        guard !isCheckingEnvironment, !phase.isActive else { return }
        let checkID = UUID()
        environmentCheckID = checkID
        let uvExecutableURL = uvExecutableURL
        let repositoryURL = repositoryURL
        let outputDirectoryURL = outputDirectoryURL
        let sourceRevision = sourceRevision

        isCheckingEnvironment = true
        environmentReport = nil
        phase = .checking
        statusMessage = "Checking uv, Xcode, repository provenance, and storage…"
        defer {
            if environmentCheckID == checkID {
                isCheckingEnvironment = false
            }
        }

        let report = await environmentDoctor.inspect(
            uvExecutableURL: uvExecutableURL,
            repositoryURL: repositoryURL,
            outputDirectoryURL: outputDirectoryURL,
            expectedRepositoryRevision: sourceRevision
        )
        guard environmentCheckID == checkID,
              !Task.isCancelled,
              !phase.isActive else {
            return
        }
        environmentReport = report
        phase = report.canConvert ? .ready : .idle
        statusMessage = report.canConvert
            ? "The environment is ready. Starting conversion may download model weights."
            : "Resolve the failed checks before starting conversion."
    }

    func selectRepository(_ url: URL) {
        guard !phase.isBusy else { return }
        repositoryURL = url
        invalidateEnvironment()
    }

    func selectOutputDirectory(_ url: URL) {
        guard !phase.isBusy else { return }
        outputDirectoryURL = url
        invalidateEnvironment()
    }

    func selectUVExecutable(_ url: URL) {
        guard !phase.isBusy else { return }
        uvExecutableURL = url
        invalidateEnvironment()
    }

    func presentImportError(_ error: any Error) {
        present(error)
    }

    func startConversion() {
        guard conversionTask == nil, canStartConversion else { return }
        phase = .checking
        statusMessage = "Revalidating the conversion environment…"
        conversionTask = Task { [weak self] in
            await self?.performConversion()
        }
    }

    func cancelConversion() {
        guard conversionTask != nil else { return }
        environmentCheckID = UUID()
        isCheckingEnvironment = false
        phase = .canceling
        statusMessage = "Sending an interrupt to the converter…"
        conversionTask?.cancel()
        Task {
            await processRunner.cancel()
        }
    }

    private func performConversion() async {
        defer {
            conversionTask = nil
            processIdentifier = nil
        }

        do {
            await refreshEnvironment()
            try Task.checkCancellation()
            guard environmentReport?.canConvert == true,
                  let command = exportCommand,
                  let selectedModel else {
                throw CoreAIConversionError.incompleteConfiguration
            }

            phase = .running
            statusMessage = "Preparing \(selectedModel.shortName)…"
            logEntries = [CoreAIConversionLogEntry(message: "$ \(command.displayString)")]
            artifacts = []
            logURL = nil
            duration = nil
            errorMessage = nil

            let result = try await processRunner.run(
                request: CoreAIConversionRequest(
                    modelName: selectedModel.shortName,
                    command: command,
                    outputDirectoryURL: outputDirectoryURL,
                    environmentChecks: environmentReport?.checks ?? []
                )
            ) { [weak self] event in
                await self?.receive(event)
            }

            artifacts = result.artifacts
            logURL = result.logURL
            duration = result.duration
            guard !result.artifacts.isEmpty else {
                throw CoreAIConversionError.noArtifactsFound
            }

            phase = .succeeded
            if result.artifacts.count == 1 {
                statusMessage = "Created 1 Core AI artifact."
            } else {
                statusMessage = "Created \(result.artifacts.count) Core AI artifacts."
            }
        } catch is CancellationError {
            phase = .canceled
            statusMessage = "The conversion was canceled. Partial downloads and outputs were left in place."
        } catch {
            phase = .failed
            present(error)
        }
    }

    private func invalidateEnvironment() {
        environmentCheckID = UUID()
        environmentReport = nil
        phase = .idle
        statusMessage = "Verify the updated conversion environment."
    }

    private func receive(_ event: CoreAIConversionProcessEvent) {
        switch event {
        case .started(let processIdentifier):
            self.processIdentifier = processIdentifier
            statusMessage = "Converter process \(processIdentifier) is running."
        case .logCreated(let url):
            logURL = url
        case .output(let line):
            appendLog(line)
            updateStatus(from: line)
        }
    }

    private func appendLog(_ line: String) {
        logEntries.append(CoreAIConversionLogEntry(message: line))
        if logEntries.count > 2_000 {
            logEntries.removeFirst(500)
        }
    }

    private func updateStatus(from line: String) {
        if line.localizedStandardContains("download") {
            statusMessage = "Downloading source weights and dependencies…"
        } else if line.localizedStandardContains("export") {
            statusMessage = "Exporting the PyTorch program…"
        } else if line.localizedStandardContains("converted") {
            statusMessage = "Lowering the exported program to Core AI…"
        } else if line.localizedStandardContains("optimized") {
            statusMessage = "Optimizing the Core AI program…"
        } else if line.localizedStandardContains("saved") {
            statusMessage = "Saving the Core AI artifact…"
        }
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        statusMessage = error.localizedDescription
        isShowingError = true
    }
}
#endif
