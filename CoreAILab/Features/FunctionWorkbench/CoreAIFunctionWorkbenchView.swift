import SwiftUI

struct CoreAIFunctionWorkbenchView: View {
    @State private var workspace = CoreAIFunctionWorkbenchWorkspaceModel()
    @State private var isImportingModel = false
    let initialURL: URL?

    init(initialURL: URL? = nil) {
        self.initialURL = initialURL
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

                        if let result = workspace.runResult {
                            CoreAIFunctionResultsView(result: result)
                        }
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
                    .disabled(workspace.phase.isBusy || workspace.assetWorkspace.phase.isBusy)
            }
        }
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [.coreAIModelAsset, .folder]
        ) { result in
            handleModelImport(result)
        }
        .background {
            CoreAIFunctionWorkbenchErrorPresenter(
                assetWorkspace: workspace.assetWorkspace
            )
        }
        .task(id: initialURL) {
            if let initialURL {
                await workspace.loadAsset(from: initialURL)
            }
        }
        .onChange(of: workspace.assetWorkspace.specializationResult) { _, result in
            Task {
                await workspace.specializationChanged(result)
            }
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
}
