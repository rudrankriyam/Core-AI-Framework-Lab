import SwiftData
import SwiftUI

struct CoreAIFunctionWorkbenchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var workspace = CoreAIFunctionWorkbenchWorkspaceModel()
    @State private var isImportingModel = false
    @State private var isChoosingExportDestination = false
    let initialURL: URL?
    let projectArtifactLink: ProjectArtifactLink?
    let projectController: CoreAIProjectLibraryController?

    init(
        initialURL: URL? = nil,
        projectArtifactLink: ProjectArtifactLink? = nil,
        projectController: CoreAIProjectLibraryController? = nil
    ) {
        self.initialURL = initialURL
        self.projectArtifactLink = projectArtifactLink
        self.projectController = projectController
    }

    var body: some View {
        Group {
            if let report = workspace.assetWorkspace.report {
                List {
                    Section("Asset") {
                        LabeledContent("Name", value: report.url.lastPathComponent)
                        LabeledContent(
                            "Device",
                            value: workspace.deviceArchitectureName
                        )
                        Text(report.url.path)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    CoreAISpecializationControlsView(
                        workspace: workspace.assetWorkspace,
                        isInteractionDisabled: workspace.phase.isBusy
                            || workspace.isExportingIntegration,
                        allowsCacheRemoval: projectArtifactLink == nil
                    )

                    if workspace.assetWorkspace.specializationResult == nil {
                        Section("Function Workbench") {
                            ContentUnavailableView(
                                "Specialize the Asset",
                                systemImage: "cpu",
                                description: Text(
                                    "Choose a compute profile above, then specialize or load its cached model to inspect runtime contracts."
                                )
                            )
                        }
                    } else if workspace.phase == .preparingContracts {
                        Section("Function Workbench") {
                            ContentUnavailableView {
                                Label("Reading Function Contracts", systemImage: "list.bullet.rectangle")
                            } description: {
                                Text("Loading input, state, and output descriptors from the specialized model.")
                            } actions: {
                                ProgressView()
                            }
                        }
                    } else if workspace.contracts.isEmpty {
                        Section("Function Workbench") {
                            ContentUnavailableView {
                                Label(
                                    workspace.contractLoadFailureMessage == nil
                                        ? "No Functions"
                                        : "Unable to Load Functions",
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
                        }
                    } else if !workspace.contracts.isEmpty {
                        CoreAIFunctionContractView(workspace: workspace)
                        CoreAIFunctionInputsView(
                            drafts: workspace.inputDrafts,
                            isDisabled: workspace.phase.isBusy
                        )

                        Section {
                            Button(
                                "Run Function",
                                systemImage: "play.fill",
                                action: runFunction
                            )
                            .buttonStyle(.borderedProminent)
                            .disabled(!workspace.canRun)

                            if workspace.phase.isBusy {
                                Label("Core AI operation in progress", systemImage: "hourglass")
                                    .foregroundStyle(.secondary)
                            }
                        } footer: {
                            Text(
                                "Generated inputs are synthetic contract probes, not semantically correct task data. Core AI inference itself cannot be canceled once started."
                            )
                        }

                        CoreAIFunctionBenchmarkControlsView(workspace: workspace)

                        if let result = workspace.runResult {
                            CoreAIFunctionResultsView(result: result)
                        }

                        if !workspace.benchmarkHistory.isEmpty {
                            CoreAIFunctionBenchmarkResultsView(
                                reports: workspace.benchmarkHistory
                            )
                        }

                        CoreAIIntegrationExportSection(
                            workspace: workspace,
                            chooseDestination: chooseExportDestination
                        )
                    }
                }
            } else if workspace.phase == .loadingAsset
                        || workspace.assetWorkspace.isInspecting {
                ContentUnavailableView {
                    Label("Opening Model", systemImage: "shippingbox")
                } description: {
                    Text("Inspecting the asset before specialization.")
                } actions: {
                    ProgressView()
                }
            } else {
                ContentUnavailableView {
                    Label("Function Workbench", systemImage: "function")
                } description: {
                    Text(
                        "Open a Core AI asset to inspect every function and run supported stateless tensor contracts with generated inputs."
                    )
                } actions: {
                    Button("Open Model", systemImage: "folder", action: openModelPicker)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Function Workbench")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Open Model", systemImage: "folder", action: openModelPicker)
                    .disabled(
                        workspace.phase.isBusy
                            || workspace.assetWorkspace.phase.isBusy
                            || workspace.isExportingIntegration
                    )
            }
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
        .background {
            CoreAIFunctionWorkbenchErrorPresenter(
                assetWorkspace: workspace.assetWorkspace
            )
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
