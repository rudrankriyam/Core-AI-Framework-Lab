import SwiftUI
import UniformTypeIdentifiers

struct AppleDiffusionWorkspaceView: View {
    @State private var workspace: AppleDiffusionWorkspaceModel
    @State private var isImportingPipeline = false
    private let initialModelURL: URL?

    init(
        example: AppleDiffusionExample,
        initialModelURL: URL? = nil,
        runContext: CoreAIRuntimeRunContext? = nil,
        runCoordinator: CoreAIRunLifecycleCoordinator? = nil
    ) {
        _workspace = State(
            initialValue: AppleDiffusionWorkspaceModel(
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
                LabeledContent("Bundle", value: workspace.modelName ?? "Not loaded")
                if let info = workspace.modelInfo {
                    LabeledContent("Pipeline", value: info.pipelineName)
                    LabeledContent("Output", value: "\(info.width) × \(info.height)")
                }
                if workspace.isBusy {
                    ProgressView(workspace.statusMessage)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            } header: {
                Label(workspace.example.title, systemImage: "wand.and.sparkles")
            }

            CoreAIRuntimeLifecycleView(
                coordinator: workspace.runCoordinator,
                context: workspace.runContext
            )

            Section {
                Button(
                    "Import Diffusion Bundle",
                    systemImage: "shippingbox",
                    action: importPipeline
                )
                .help("Choose a folder produced by coreai.diffusion.export.")
            } header: {
                Label("Pipeline Bundle", systemImage: "shippingbox")
            }

            Section {
                TextField("Describe an image", text: $workspace.prompt, axis: .vertical)
                    .lineLimit(3...8)
                    .disabled(!workspace.canEditGenerationInputs)
                if workspace.modelInfo?.supportsNegativePrompt == false {
                    LabeledContent("Negative prompt", value: "Not supported")
                } else {
                    TextField("Negative prompt", text: $workspace.negativePrompt, axis: .vertical)
                        .lineLimit(2...5)
                        .disabled(!workspace.canEditGenerationInputs)
                }

                Stepper("Seed: \(workspace.seed)", value: $workspace.seed, in: 0...Int(UInt32.max))
                    .disabled(!workspace.canEditGenerationInputs)
                Stepper("Steps: \(workspace.stepCount)", value: $workspace.stepCount, in: 1...100)
                    .disabled(!workspace.canEditGenerationInputs)
                LabeledContent("Guidance: \(workspace.guidanceScale.formatted(.number.precision(.fractionLength(1))))") {
                    Slider(value: $workspace.guidanceScale, in: 0...20, step: 0.5)
                        .frame(minWidth: 160)
                        .disabled(!workspace.canEditGenerationInputs)
                }

#if !os(macOS)
                ViewThatFits(in: .horizontal) {
                    generationActions(axis: .horizontal)
                    generationActions(axis: .vertical)
                }
#endif
            } header: {
                Label("Prompt", systemImage: "text.bubble")
            }

            AppleDiffusionResultView(result: workspace.result)
        }
        .formStyle(.grouped)
        .navigationTitle("Diffusion Playground")
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
            isPresented: $isImportingPipeline,
            allowedContentTypes: [.folder]
        ) { result in
            handlePipelineImport(result)
        }
        .alert("Couldn't Generate the Image", isPresented: $workspace.isShowingError) {
        } message: {
            Text(workspace.errorMessage ?? "Check the pipeline bundle and prompt, then try again.")
        }
        .task(id: initialModelURL) {
            if let initialModelURL {
                await workspace.loadPipeline(from: initialModelURL)
            }
        }
        .onDisappear(perform: workspace.cancelGeneration)
    }

    private func importPipeline() {
        isImportingPipeline = true
    }

    private func handlePipelineImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            Task {
                await workspace.loadPipeline(from: url)
            }
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                workspace.presentImportError(error)
            }
        }
    }

#if !os(macOS)
    private func generationActions(axis: Axis) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout())
            : AnyLayout(VStackLayout(alignment: .leading))

        return layout {
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
}
