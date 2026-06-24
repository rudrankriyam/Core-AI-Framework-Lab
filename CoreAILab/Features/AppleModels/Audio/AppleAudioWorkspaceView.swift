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
                if workspace.isBusy {
                    ProgressView(workspace.statusMessage)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            } header: {
                Label(workspace.example.title, systemImage: "waveform.badge.mic")
            }

            CoreAIRuntimeLifecycleView(
                coordinator: workspace.runCoordinator,
                context: workspace.runContext
            )

            Section {
                ViewThatFits(in: .horizontal) {
                    inputActions(axis: .horizontal)
                    inputActions(axis: .vertical)
                }

            } header: {
                Label("Model & Audio", systemImage: "waveform.badge.mic")
            }
            .help("Audio is limited to five seconds and prepared as 16 kHz mono before inference.")

            Section {
                Text(workspace.example.exportCommand)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            } header: {
                Label("Apple Export Command", systemImage: "terminal")
            }

            AppleAudioTranscriptionResultView(result: workspace.result)
        }
        .formStyle(.grouped)
        .navigationTitle("Audio Transcription")
        .toolbar {
#if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                if workspace.isTranscribing {
                    Button(
                        "Cancel Transcription",
                        systemImage: "stop.fill",
                        role: .cancel,
                        action: workspace.cancelTranscription
                    )
                } else {
                    Button(
                        "Transcribe",
                        systemImage: "captions.bubble",
                        action: workspace.startTranscription
                    )
                    .disabled(!workspace.canTranscribe)
                    .help(workspace.statusMessage)
                }
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
            isPresented: $isImportingAudio,
            allowedContentTypes: [.audio]
        ) { result in
            handleAudioImport(result)
        }
        .alert("Couldn't Transcribe Audio", isPresented: $workspace.isShowingError) {
        } message: {
            Text(workspace.errorMessage ?? "Check the model and audio files, then try again.")
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
            presentSelectionError(error)
        }
    }

    private func handleAudioImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            workspace.selectAudio(url)
        case .failure(let error):
            presentSelectionError(error)
        }
    }

    private func inputActions(axis: Axis) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout())
            : AnyLayout(VStackLayout(alignment: .leading))

        return layout {
            Button("Import Wav2Vec2 Model", systemImage: "shippingbox", action: importModel)
            Button("Choose Audio", systemImage: "waveform", action: importAudio)
#if !os(macOS)
            Button("Transcribe", systemImage: "captions.bubble", action: workspace.startTranscription)
                .buttonStyle(.borderedProminent)
                .disabled(!workspace.canTranscribe)
            if workspace.isTranscribing {
                Button(
                    "Cancel",
                    systemImage: "stop.fill",
                    role: .cancel,
                    action: workspace.cancelTranscription
                )
            }
#endif
        }
    }

    private func presentSelectionError(_ error: any Error) {
        if (error as? CocoaError)?.code != .userCancelled {
            workspace.presentImportError(error)
        }
    }
}
