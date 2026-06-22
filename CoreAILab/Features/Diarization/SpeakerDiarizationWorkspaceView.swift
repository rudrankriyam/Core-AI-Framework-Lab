import SwiftUI
import UniformTypeIdentifiers

struct SpeakerDiarizationWorkspaceView: View {
    @State private var workspace = SpeakerDiarizationWorkspaceModel()
    @State private var watcher = SpeakerDiarizationWatcherModel()
    @State private var isImportingModel = false
    @State private var isImportingMedia = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                Form {
                    SpeakerDiarizationStatusSection(
                        modelInfo: workspace.modelInfo,
                        summary: workspace.mediaSummary,
                        statusMessage: workspace.statusMessage,
                        isBusy: workspace.isBusy
                    )

                    SpeakerDiarizationImportSection(
                        canRunDiarization: workspace.canRunDiarization,
                        isBusy: workspace.isBusy,
                        importModelAction: importModel,
                        importMediaAction: importMedia,
                        runAction: workspace.startDiarization
                    )

                    SpeakerDiarizationWatcherSection(
                        summary: workspace.mediaSummary,
                        player: watcher.player,
                        currentTime: watcher.currentTime,
                        activeTurn: workspace.result?.turn(at: watcher.currentTime),
                        isPlaying: watcher.isPlaying,
                        togglePlayback: watcher.togglePlayback,
                        restart: watcher.restart
                    )

                    SpeakerDiarizationAnalysisSection(
                        availableWidth: geometry.size.width,
                        waveform: workspace.waveform,
                        result: workspace.result,
                        playheadTime: watcher.currentTime,
                        activeTurnID: workspace.result?.turn(at: watcher.currentTime)?.id
                    )
                }
                .formStyle(.grouped)
            }
            .navigationTitle("Diarization")
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
            .alert("Diarization Lab Failed", isPresented: $workspace.isShowingError) {
            } message: {
                Text(workspace.errorMessage ?? "The request could not be completed.")
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
            workspace.presentImportError(error)
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
