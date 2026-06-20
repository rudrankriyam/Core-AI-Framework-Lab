import SwiftUI
import UniformTypeIdentifiers

struct AppleDiffusionWorkspaceView: View {
    @State private var workspace: AppleDiffusionWorkspaceModel
    @State private var isImportingPipeline = false
    private let initialModelURL: URL?

    init(
        example: AppleDiffusionExample,
        initialModelURL: URL? = nil
    ) {
        _workspace = State(initialValue: AppleDiffusionWorkspaceModel(example: example))
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
                Label(
                    workspace.statusMessage,
                    systemImage: workspace.isBusy ? "hourglass" : "wand.and.sparkles"
                )
                .foregroundStyle(workspace.isBusy ? .primary : .secondary)
            } header: {
                Label(workspace.example.title, systemImage: "wand.and.sparkles")
            }

            Section("Pipeline Bundle") {
                Button(
                    "Import Diffusion Bundle",
                    systemImage: "shippingbox",
                    action: importPipeline
                )
                Text("Import the entire folder produced by `coreai.diffusion.export`. The Lab reads its metadata and selects Apple's Stable Diffusion, SD3, or FLUX.2 runtime automatically.")
                    .foregroundStyle(.secondary)
            }

            Section("Prompt") {
                TextField("Describe an image", text: $workspace.prompt, axis: .vertical)
                    .lineLimit(3...8)
                if workspace.modelInfo?.supportsNegativePrompt == false {
                    Text("FLUX.2 does not consume a negative prompt.")
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Negative prompt", text: $workspace.negativePrompt, axis: .vertical)
                        .lineLimit(2...5)
                }

                Stepper("Seed: \(workspace.seed)", value: $workspace.seed, in: 0...Int(UInt32.max))
                Stepper("Steps: \(workspace.stepCount)", value: $workspace.stepCount, in: 1...100)
                LabeledContent("Guidance: \(workspace.guidanceScale.formatted(.number.precision(.fractionLength(1))))") {
                    Slider(value: $workspace.guidanceScale, in: 0...20, step: 0.5)
                        .frame(minWidth: 160)
                }

                HStack {
                    Button("Generate", systemImage: "play.fill", action: workspace.startGeneration)
                        .buttonStyle(.borderedProminent)
                        .disabled(!workspace.canGenerate)
                    if workspace.isGenerating {
                        Button(
                            "Cancel",
                            systemImage: "stop.fill",
                            role: .destructive,
                            action: workspace.cancelGeneration
                        )
                    }
                }
            }

            AppleDiffusionResultView(result: workspace.result)
        }
        .formStyle(.grouped)
        .navigationTitle("Diffusion Playground")
        .fileImporter(
            isPresented: $isImportingPipeline,
            allowedContentTypes: [.folder]
        ) { result in
            handlePipelineImport(result)
        }
        .alert("Diffusion Failed", isPresented: $workspace.isShowingError) {
        } message: {
            Text(workspace.errorMessage ?? "The request could not be completed.")
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
            workspace.presentImportError(error)
        }
    }
}
