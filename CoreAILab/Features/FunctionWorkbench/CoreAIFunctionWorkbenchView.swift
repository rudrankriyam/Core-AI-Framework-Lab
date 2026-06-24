import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CoreAIFunctionWorkbenchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var workspace: CoreAIFunctionWorkbenchWorkspaceModel
    @State private var isImportingModel = false
    @State private var isChoosingExportDestination = false
    @State private var benchmarkEvidenceFile: CoreAIBenchmarkEvidenceFileDocument?
    @State private var benchmarkEvidenceFilename = "coreai-benchmark-evidence"
    @State private var isExportingBenchmarkEvidence = false
    private let initialURL: URL?
    private let projectArtifactLink: ProjectArtifactLink?
    private let projectController: CoreAIProjectLibraryController?

    init(
        initialURL: URL? = nil,
        projectArtifactLink: ProjectArtifactLink? = nil,
        projectController: CoreAIProjectLibraryController? = nil,
        runContext: CoreAIRuntimeRunContext? = nil,
        runCoordinator: CoreAIRunLifecycleCoordinator? = nil
    ) {
        _workspace = State(
            initialValue: CoreAIFunctionWorkbenchWorkspaceModel(
                runContext: runContext,
                runCoordinator: runCoordinator
            )
        )
        self.initialURL = initialURL
        self.projectArtifactLink = projectArtifactLink
        self.projectController = projectController
    }

    var body: some View {
        @Bindable var assetWorkspace = workspace.assetWorkspace

        Group {
            if let report = workspace.assetWorkspace.report {
                Form {
                    Section {
                        LabeledContent("Name", value: report.url.lastPathComponent)
                        LabeledContent(
                            "Device",
                            value: workspace.deviceArchitectureName
                        )
                        Text(report.url.path)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    } header: {
                        Label("Asset", systemImage: "shippingbox")
                    }

                    CoreAIRuntimeLifecycleView(
                        coordinator: workspace.runCoordinator,
                        context: workspace.runContext
                    )

                    CoreAISpecializationControlsView(
                        workspace: workspace.assetWorkspace,
                        isInteractionDisabled: workspace.phase.isBusy
                            || workspace.isExportingIntegration,
                        allowsCacheRemoval: projectArtifactLink == nil
                    )

                    if workspace.assetWorkspace.specializationResult == nil {
                        Section {
                            ContentUnavailableView(
                                "Specialize the Asset",
                                systemImage: "cpu"
                            )
                            .help("Choose a compute profile, then specialize or load its cached model.")
                        } header: {
                            Label("Function Workbench", systemImage: "function")
                        }
                    } else if workspace.phase == .preparingContracts {
                        Section {
                            ContentUnavailableView {
                                Label("Reading Function Contracts", systemImage: "list.bullet.rectangle")
                            } actions: {
                                ProgressView()
                            }
                        } header: {
                            Label("Function Workbench", systemImage: "function")
                        }
                    } else if workspace.contracts.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label(
                                    workspace.contractLoadFailureMessage == nil
                                        ? "No Functions"
                                        : "Couldn't Read Functions",
                                    systemImage: workspace.contractLoadFailureMessage == nil
                                        ? "function"
                                        : "exclamationmark.triangle"
                                )
                            } description: {
                                Text(
                                    workspace.contractLoadFailureMessage
                                        ?? "Core AI returned no function descriptors for this specialized model."
                                )
                            } actions: {
                                if workspace.contractLoadFailureMessage != nil {
                                    Button(
                                        "Reload Contracts",
                                        systemImage: "arrow.clockwise",
                                        action: reloadContracts
                                    )
                                }
                            }
                        } header: {
                            Label("Function Workbench", systemImage: "function")
                        }
                    } else {
                        CoreAIFunctionContractView(workspace: workspace)
                        CoreAIFunctionInputsView(
                            drafts: workspace.inputDrafts,
                            isDisabled: workspace.phase.isBusy
                        )

                        if workspace.phase == .running {
                            Section {
                                ProgressView(
                                    "Running \(workspace.selectedFunctionName ?? "function")…"
                                )
                                .accessibilityAddTraits(.updatesFrequently)
                            } header: {
                                Label("Run", systemImage: "play.fill")
                            }
                        }

#if !os(macOS)
                        Section {
                            Button(
                                "Run Function",
                                systemImage: "play.fill",
                                action: runFunction
                            )
                            .buttonStyle(.borderedProminent)
                            .disabled(!workspace.canRun)
                        } header: {
                            Label("Run", systemImage: "play.fill")
                        }
#endif

                        CoreAIFunctionBenchmarkControlsView(workspace: workspace)

                        if let result = workspace.runResult {
                            CoreAIFunctionResultsView(result: result)
                        }

                        if !workspace.benchmarkHistory.isEmpty {
                            CoreAIFunctionBenchmarkResultsView(
                                reports: workspace.benchmarkHistory,
                                exportEvidence: prepareBenchmarkEvidenceExport
                            )
                        }

                        CoreAIIntegrationExportSection(
                            workspace: workspace,
                            chooseDestination: chooseExportDestination
                        )
                    }
                }
                .formStyle(.grouped)
            } else if workspace.phase == .loadingAsset
                        || workspace.assetWorkspace.isInspecting {
                ContentUnavailableView {
                    Label("Opening Model", systemImage: "shippingbox")
                } actions: {
                    ProgressView()
                }
            } else {
                ContentUnavailableView {
                    Label("Function Workbench", systemImage: "function")
                } actions: {
                    Button("Open Model", systemImage: "folder", action: openModelPicker)
                        .buttonStyle(.borderedProminent)
                }
                .help("Open a Core AI asset to inspect its functions and supported tensor contracts.")
            }
        }
        .navigationTitle("Function Workbench")
        .toolbar {
#if os(macOS)
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Open Model", systemImage: "folder", action: openModelPicker)
                    .disabled(
                        workspace.phase.isBusy
                            || workspace.assetWorkspace.phase.isBusy
                            || workspace.isExportingIntegration
                    )
                    .keyboardShortcut("o", modifiers: .command)

                Button("Run Function", systemImage: "play.fill", action: runFunction)
                    .disabled(!workspace.canRun)
                    .help(
                        "Run synthetic contract inputs. Core AI inference cannot be canceled once started."
                    )
            }
#else
            ToolbarItem(placement: .primaryAction) {
                Button("Open Model", systemImage: "folder", action: openModelPicker)
                    .disabled(
                        workspace.phase.isBusy
                            || workspace.assetWorkspace.phase.isBusy
                            || workspace.isExportingIntegration
                    )
                    .keyboardShortcut("o", modifiers: .command)
            }
#endif
        }
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [.coreAIModelAsset, .folder]
        ) { result in
            handleModelImport(result)
        }
        .fileImporter(
            isPresented: $isChoosingExportDestination,
            allowedContentTypes: [.folder]
        ) { result in
            handleExportDestination(result)
        }
        .fileExporter(
            isPresented: $isExportingBenchmarkEvidence,
            document: benchmarkEvidenceFile,
            contentType: .json,
            defaultFilename: benchmarkEvidenceFilename
        ) { result in
            handleBenchmarkEvidenceExport(result)
        }
        .alert(
            "Couldn't Complete the Core AI Operation",
            isPresented: $assetWorkspace.isShowingError
        ) {
        } message: {
            Text(assetWorkspace.errorMessage ?? "Check the model and configuration, then try again.")
        }
        .task(id: initialURL) {
            do {
                if let initialURL = try resolvedInitialURL() {
                    await workspace.loadAsset(from: initialURL)
                }
            } catch {
                workspace.presentImportError(error)
            }
        }
        .task(id: workspace.assetWorkspace.specializationResult) {
            await workspace.specializationChanged(
                workspace.assetWorkspace.specializationResult
            )
        }
        .onChange(of: workspace.assetWorkspace.report) { _, report in
            persistDescriptorSnapshot(report)
        }
        .onChange(of: workspace.assetWorkspace.specializationResult) { _, result in
            Task {
                await persistSpecialization(result)
            }
        }
        .onDisappear {
            workspace.cancelBenchmark()
            workspace.cancelIntegrationExport()
        }
    }

    private func openModelPicker() {
        isImportingModel = true
    }

    private func handleModelImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            Task {
                await workspace.loadAsset(from: url)
            }
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                workspace.presentImportError(error)
            }
        }
    }

    private func runFunction() {
        Task {
            await workspace.runSelectedFunction()
        }
    }

    private func chooseExportDestination() {
        isChoosingExportDestination = true
    }

    private func handleExportDestination(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            workspace.startIntegrationExport(to: url)
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                workspace.presentImportError(error)
            }
        }
    }

    private func reloadContracts() {
        Task {
            await workspace.reloadContracts()
        }
    }

    private func prepareBenchmarkEvidenceExport(
        _ report: CoreAIFunctionBenchmarkReport
    ) {
        do {
            let document = CoreAIBenchmarkEvidenceDocument(report: report)
            let data = try CoreAIBenchmarkEvidenceCodec().encode(document)
            benchmarkEvidenceFile = CoreAIBenchmarkEvidenceFileDocument(
                data: data
            )
            benchmarkEvidenceFilename = "coreai-benchmark-\(report.id.uuidString.lowercased())"
            isExportingBenchmarkEvidence = true
        } catch {
            workspace.presentImportError(error)
        }
    }

    private func persistDescriptorSnapshot(_ report: CoreAIModelAssetReport?) {
        guard let report,
              let projectArtifactLink,
              let projectController,
              isProjectArtifact(report.url) else { return }
        do {
            try projectController.recordDescriptorSnapshot(
                report,
                for: projectArtifactLink,
                modelContext: modelContext
            )
        } catch {
            workspace.presentImportError(error)
        }
    }

    private func handleBenchmarkEvidenceExport(
        _ result: Result<URL, any Error>
    ) {
        benchmarkEvidenceFile = nil
        if case .failure(let error) = result,
           (error as? CocoaError)?.code != .userCancelled {
            workspace.presentImportError(error)
        }
    }

    private func persistSpecialization(
        _ result: CoreAISpecializationResult?
    ) async {
        guard let result,
              let sourceURL = workspace.assetWorkspace.report?.url,
              let projectArtifactLink,
              let projectController,
              isProjectArtifact(sourceURL) else { return }
        do {
            try await projectController.recordSpecializationCache(
                result,
                sourceURL: sourceURL,
                for: projectArtifactLink,
                modelContext: modelContext
            )
        } catch {
            workspace.presentImportError(error)
        }
    }

    private func isProjectArtifact(_ url: URL) -> Bool {
        guard let artifact = projectArtifactLink?.artifact,
              let projectController,
              let storedURL = try? projectController.validatedStoredURL(for: artifact) else {
            return false
        }
        return url.standardizedFileURL
            == storedURL.standardizedFileURL
    }

    private func resolvedInitialURL() throws -> URL? {
        guard let artifact = projectArtifactLink?.artifact,
              let projectController else {
            return initialURL
        }
        return try projectController.validatedStoredURL(for: artifact)
    }
}
