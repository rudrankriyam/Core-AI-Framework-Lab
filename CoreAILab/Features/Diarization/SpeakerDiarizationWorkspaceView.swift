import SwiftUI
import UniformTypeIdentifiers

struct SpeakerDiarizationWorkspaceView: View {
    @State private var workspace = SpeakerDiarizationWorkspaceModel()
    @State private var watcher = SpeakerDiarizationWatcherModel()
    @State private var isImportingMedia = false

    var body: some View {
        NavigationStack {
            Form {
                SpeakerDiarizationStatusSection(
                    summary: workspace.mediaSummary,
                    statusMessage: workspace.statusMessage,
                    isBusy: workspace.isBusy
                )

                SpeakerDiarizationImportSection(
                    canRunStub: workspace.canRunStub,
                    isRunningStub: workspace.isRunningStub,
                    importAction: importMedia,
                    runAction: workspace.runStubDiarization
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

                SpeakerDiarizationTimelineView(
                    waveform: workspace.waveform,
                    result: workspace.result,
                    playheadTime: watcher.currentTime
                )

                SpeakerDiarizationResultsView(
                    result: workspace.result,
                    activeTurnID: workspace.result?.turn(at: watcher.currentTime)?.id
                )
            }
            .formStyle(.grouped)
            .navigationTitle("Diarization")
            .onChange(of: workspace.mediaSummary) { _, summary in
                watcher.load(url: workspace.mediaURL, summary: summary)
            }
            .onDisappear {
                watcher.reset()
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
}
