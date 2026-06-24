import SwiftUI
import UniformTypeIdentifiers

struct SpeakerDiarizationWorkspaceView: View {
    @State private var workspace = SpeakerDiarizationWorkspaceModel()
    @State private var watcher = SpeakerDiarizationWatcherModel()
    @State private var isImportingModel = false
    @State private var isImportingMedia = false

    var body: some View {
        let activeTurn = workspace.result?.turn(at: watcher.currentTime)

        NavigationStack {
            Form {
                SpeakerDiarizationStatusSection(
                    modelInfo: workspace.modelInfo,
                    summary: workspace.mediaSummary,
                    statusMessage: workspace.statusMessage,
                    isBusy: workspace.isBusy
                )

                SpeakerDiarizationImportSection(
                    canRunDiarization: workspace.canRunDiarization,
                    canImportModel: !workspace.isLoadingModel
                        && !workspace.isRunningDiarization,
                    canImportMedia: !workspace.isAnalyzingMedia
                        && !workspace.isRunningDiarization,
                    importModelAction: importModel,
                    importMediaAction: importMedia,
                    runAction: workspace.startDiarization
                )

                SpeakerDiarizationWatcherSection(
                    summary: workspace.mediaSummary,
                    player: watcher.player,
                    currentTime: watcher.currentTime,
                    activeTurn: activeTurn,
                    isPlaying: watcher.isPlaying,
                    togglePlayback: watcher.togglePlayback,
                    restart: watcher.restart
                )

                SpeakerDiarizationAnalysisSection(
                    waveform: workspace.waveform,
                    result: workspace.result,
                    playheadTime: watcher.currentTime,
                    activeTurnID: activeTurn?.id
                )
            }
            .formStyle(.grouped)
            .navigationTitle("Diarization")
            .task {
                await workspace.prepareBundledModel()
            }
            .onChange(of: workspace.mediaSummary) { _, summary in
                watcher.load(url: workspace.mediaURL, summary: summary)
            }
            .onDisappear {
                watcher.reset()
                workspace.cancelWork()
            }
            .fileImporter(
                isPresented: $isImportingModel,
                allowedContentTypes: [.coreAIModelAsset, .folder]
            ) { result in
                handleModelImport(result)
            }
            .fileImporter(
                isPresented: $isImportingMedia,
                allowedContentTypes: [.audio, .movie]
            ) { result in
                handleMediaImport(result)
            }
            .alert("Couldn't Separate the Speakers", isPresented: $workspace.isShowingError) {
            } message: {
                Text(workspace.errorMessage ?? "Check the model and media file, then try again.")
            }
        }
    }

    private func importModel() {
        isImportingModel = true
    }

    private func importMedia() {
        isImportingMedia = true
    }

    private func handleMediaImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            workspace.selectMedia(url)
        case .failure(let error):
            presentSelectionError(error)
        }
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

    private func presentSelectionError(_ error: any Error) {
        if (error as? CocoaError)?.code != .userCancelled {
            workspace.presentImportError(error)
        }
    }
}
