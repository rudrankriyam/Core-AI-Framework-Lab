import SwiftUI
import UniformTypeIdentifiers

struct AppleAudioWorkspaceView: View {
    @State private var workspace: AppleAudioWorkspaceModel
    @State private var isImportingModel = false
    @State private var isImportingAudio = false
    private let initialModelURL: URL?

    init(
        example: AppleAudioExample = .wav2Vec2,
        initialModelURL: URL? = nil,
        runContext: CoreAIRuntimeRunContext? = nil,
        runCoordinator: CoreAIRunLifecycleCoordinator? = nil
    ) {
        _workspace = State(
            initialValue: AppleAudioWorkspaceModel(
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
                LabeledContent("Audio", value: workspace.audioName ?? "Not selected")
                if let info = workspace.modelInfo {
                    LabeledContent("Input", value: "1 × \(info.sampleCount) \(info.scalarTypeName)")
                    LabeledContent("Sample rate", value: "\(Int(info.sampleRate).formatted()) Hz mono")
                }
                Label(
                    workspace.statusMessage,
                    systemImage: workspace.isBusy ? "hourglass" : "waveform"
                )
                .foregroundStyle(workspace.isBusy ? .primary : .secondary)
            } header: {
                Label(workspace.example.title, systemImage: "waveform.badge.mic")
            }

            CoreAIRuntimeLifecycleView(
                coordinator: workspace.runCoordinator,
                context: workspace.runContext
            )

            Section("Inputs") {
                HStack {
                    Button("Import Wav2Vec2", systemImage: "shippingbox", action: importModel)
                    Button("Choose Audio", systemImage: "waveform", action: importAudio)
                    Button("Transcribe", systemImage: "captions.bubble", action: workspace.startTranscription)
                        .buttonStyle(.borderedProminent)
                        .disabled(!workspace.canTranscribe)
                    if workspace.isTranscribing {
                        Button(
                            "Cancel",
                            systemImage: "stop.fill",
                            role: .destructive,
                            action: workspace.cancelTranscription
                        )
                    }
                }

                Text("The static Apple recipe accepts at most five seconds. Audio is decoded, downmixed, and resampled to 16 kHz mono before inference.")
                    .foregroundStyle(.secondary)
            }

            Section("Apple Export Command") {
                Text(workspace.example.exportCommand)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }

            AppleAudioTranscriptionResultView(result: workspace.result)
        }
        .formStyle(.grouped)
        .navigationTitle("Audio Transcription")
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [.coreAIModelAsset, .folder]
        ) { result in
            handleModelImport(result)
        }
        .fileImporter(
            isPresented: $isImportingAudio,
            allowedContentTypes: [.audio]
        ) { result in
            handleAudioImport(result)
        }
        .alert("Audio Transcription Failed", isPresented: $workspace.isShowingError) {
        } message: {
            Text(workspace.errorMessage ?? "The request could not be completed.")
        }
        .task(id: initialModelURL) {
            if let initialModelURL {
                await workspace.loadModel(from: initialModelURL)
            }
        }
        .onDisappear(perform: workspace.cancelTranscription)
    }

    private func importModel() {
        isImportingModel = true
    }

    private func importAudio() {
        isImportingAudio = true
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

    private func handleAudioImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            workspace.selectAudio(url)
        case .failure(let error):
            workspace.presentImportError(error)
        }
    }
}
