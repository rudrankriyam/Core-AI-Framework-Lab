import SwiftUI
import UniformTypeIdentifiers

struct AppleLanguageWorkspaceView: View {
    @State private var workspace: AppleLanguageWorkspaceModel
    @State private var isImportingModel = false
    private let initialModelURL: URL?

    init(
        example: AppleLanguageExample,
        initialModelURL: URL? = nil,
        runContext: CoreAIRuntimeRunContext? = nil,
        runCoordinator: CoreAIRunLifecycleCoordinator? = nil
    ) {
        _workspace = State(
            initialValue: AppleLanguageWorkspaceModel(
                example: example,
                runContext: runContext,
                runCoordinator: runCoordinator
            )
        )
        self.initialModelURL = initialModelURL
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Model", value: workspace.modelName ?? "Not loaded")
                if workspace.isBusy {
                    ProgressView(workspace.statusMessage)
                        .accessibilityAddTraits(.updatesFrequently)
                } else {
                    Label(workspace.statusMessage, systemImage: "text.bubble")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label(workspace.example.title, systemImage: "text.bubble.fill")
            }

            CoreAIRuntimeLifecycleView(
                coordinator: workspace.runCoordinator,
                context: workspace.runContext
            )

            Section {
                ViewThatFits(in: .horizontal) {
                    modelActions(axis: .horizontal)
                    modelActions(axis: .vertical)
                }

                LabeledContent("macOS export") {
                    Text(workspace.example.macOSExportCommand)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("iOS export") {
                    Text(workspace.example.iOSExportCommand)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            } header: {
                Label("Model Bundle", systemImage: "shippingbox")
            }

            Section {
                TextField("Ask Qwen", text: $workspace.prompt, axis: .vertical)
                    .lineLimit(3...8)
                    .disabled(!workspace.canEditGenerationInputs)
                Stepper(
                    "Maximum response tokens: \(workspace.maximumResponseTokens)",
                    value: $workspace.maximumResponseTokens,
                    in: 1...512,
                    step: 16
                )
                .disabled(!workspace.canEditGenerationInputs)

#if !os(macOS)
                ViewThatFits(in: .horizontal) {
                    generationActions(axis: .horizontal)
                    generationActions(axis: .vertical)
                }
#endif
            } header: {
                Label("Prompt", systemImage: "text.bubble")
            }

            AppleLanguageResponseView(response: workspace.response)
        }
        .formStyle(.grouped)
        .navigationTitle("\(workspace.example.title) Language Model")
        .toolbar {
#if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                if workspace.isGenerating {
                    Button(
                        "Cancel Generation",
                        systemImage: "stop.fill",
                        role: .cancel,
                        action: workspace.cancelGeneration
                    )
                } else {
                    Button("Generate", systemImage: "play.fill", action: workspace.startGeneration)
                        .disabled(!workspace.canGenerate)
                        .help(workspace.statusMessage)
                }
            }
#endif
        }
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [.folder]
        ) { result in
            handleModelImport(result)
        }
        .alert("Couldn't Generate a Response", isPresented: $workspace.isShowingError) {
        } message: {
            Text(workspace.errorMessage ?? "Check the model bundle and prompt, then try again.")
        }
        .task(id: initialModelURL) {
            if let initialModelURL {
                await workspace.loadModel(from: initialModelURL)
            }
        }
        .onDisappear(perform: workspace.cancelGeneration)
    }

    private func importModel() {
        isImportingModel = true
    }

    private func resetSession() {
        Task {
            await workspace.resetSession()
        }
    }

    private func handleModelImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            Task {
                await workspace.loadModel(from: url)
            }
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                workspace.presentImportError(error)
            }
        }
    }

    private func modelActions(axis: Axis) -> some View {
        adaptiveLayout(axis: axis) {
            Button("Import Qwen Bundle", systemImage: "shippingbox", action: importModel)
            Button("New Session", systemImage: "arrow.counterclockwise", action: resetSession)
                .disabled(workspace.modelName == nil || workspace.isBusy)
        }
    }

#if !os(macOS)
    private func generationActions(axis: Axis) -> some View {
        adaptiveLayout(axis: axis) {
            Button("Generate", systemImage: "play.fill", action: workspace.startGeneration)
                .buttonStyle(.borderedProminent)
                .disabled(!workspace.canGenerate)
            if workspace.isGenerating {
                Button(
                    "Cancel",
                    systemImage: "stop.fill",
                    role: .cancel,
                    action: workspace.cancelGeneration
                )
            }
        }
    }
#endif

    private func adaptiveLayout<Content: View>(
        axis: Axis,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout())
            : AnyLayout(VStackLayout(alignment: .leading))
        return layout {
            content()
        }
    }
}
