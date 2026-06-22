import AVKit
import SwiftUI

struct SpeakerDiarizationWatcherSection: View {
    let summary: SpeakerDiarizationMediaSummary?
    let player: AVPlayer?
    let currentTime: Double
    let activeTurn: SpeakerDiarizationTurn?
    let isPlaying: Bool
    let togglePlayback: () -> Void
    let restart: () -> Void

    var body: some View {
        Section("Playback Watcher") {
            if let summary, let player {
                if summary.kind == .video {
                    VideoPlayer(player: player)
                        .frame(minHeight: 220)
                        .clipShape(.rect(cornerRadius: 14))
                        .accessibilityLabel("Imported video preview")
                } else {
                    ContentUnavailableView(
                        "Audio Watcher",
                        systemImage: "waveform.circle",
                        description: Text("Playback still drives the same live playhead and active speaker state.")
                    )
                }

                LabeledContent("Position", value: positionText(for: summary))
                LabeledContent("Active speaker", value: activeTurn?.speakerName ?? "Waiting for turns")

                HStack {
                    Button(
                        isPlaying ? "Pause Watcher" : "Play Watcher",
                        systemImage: isPlaying ? "pause.fill" : "play.fill",
                        action: togglePlayback
                    )
                    .buttonStyle(.borderedProminent)

                    Button("Restart", systemImage: "backward.end.fill", action: restart)
                }

                Text("The watcher synchronizes playback with the timeline. It is not streaming real diarization inference yet.")
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    "No Media to Watch",
                    systemImage: "play.rectangle",
                    description: Text("Import audio or video to enable synchronized playback.")
                )
            }
        }
    }

    private func positionText(for summary: SpeakerDiarizationMediaSummary) -> String {
        "\(SpeakerDiarizationTimeFormatter.format(currentTime)) / \(SpeakerDiarizationTimeFormatter.format(summary.durationSeconds))"
    }
}
