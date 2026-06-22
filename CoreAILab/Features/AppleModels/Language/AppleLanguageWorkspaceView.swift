import SwiftUI
import UniformTypeIdentifiers

struct AppleLanguageWorkspaceView: View {
    @State private var workspace: AppleLanguageWorkspaceModel
    @State private var isImportingModel = false
    private let initialModelURL: URL?
    private let runContext: CoreAIRuntimeRunContext

    init(
        example: AppleLanguageExample,
        initialModelURL: URL? = nil,
        runContext: CoreAIRuntimeRunContext? = nil,
        runCoordinator: CoreAIRunLifecycleCoordinator? = nil
    ) {
        let resolvedContext = runContext ?? .workspaceDefault(
            experienceID: "apple-language-\(example.rawValue)",
            title: example.title,
            modelIdentifier: "qwen3-0.6b"
        )
        _workspace = State(
            initialValue: AppleLanguageWorkspaceModel(
                example: example,
                runContext: resolvedContext,
                runCoordinator: runCoordinator
            )
        )
        self.initialModelURL = initialModelURL
        self.runContext = resolvedContext
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Model", value: workspace.modelName ?? "Not loaded")
                Label(
                    workspace.statusMessage,
                    systemImage: workspace.isBusy ? "hourglass" : "text.bubble"
                )
                .foregroundStyle(workspace.isBusy ? .primary : .secondary)
            } header: {
                Label(workspace.example.title, systemImage: "text.bubble.fill")
            }

            CoreAIRuntimeLifecycleView(
                coordinator: workspace.runCoordinator,
                context: runContext
            )

            Section("Model Bundle") {
                HStack {
                    Button("Import Qwen Bundle", systemImage: "shippingbox", action: importModel)
                    Button("New Session", systemImage: "arrow.counterclockwise", action: resetSession)
                        .disabled(workspace.modelName == nil || workspace.isBusy)
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
            }

            Section("Prompt") {
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

                HStack {
                    Button("Generate", systemImage: "play.fill", action: workspace.startGeneration)
                        .buttonStyle(.borderedProminent)
                        .disabled(!workspace.canGenerate)
                    if workspace.isGenerating {
                        Button("Cancel", systemImage: "stop.fill", role: .destructive, action: workspace.cancelGeneration)
                    }
                }
            }

            AppleLanguageResponseView(response: workspace.response)
        }
        .formStyle(.grouped)
        .navigationTitle("\(workspace.example.title) Language Model")
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [.folder]
        ) { result in
            handleModelImport(result)
        }
        .alert("Language Model Failed", isPresented: $workspace.isShowingError) {
        } message: {
            Text(workspace.errorMessage ?? "The request could not be completed.")
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
            workspace.presentImportError(error)
        }
    }
}
