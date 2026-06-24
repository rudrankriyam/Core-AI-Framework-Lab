import AVFoundation
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
                    SpeakerDiarizationVideoPlayer(player: player)
                        .frame(minHeight: 220)
                        .clipShape(.rect(cornerRadius: 14))
                        .accessibilityLabel("Imported video preview")
                } else {
                    ContentUnavailableView(
                        "Audio Watcher",
                        systemImage: "waveform.circle"
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

            } else {
                ContentUnavailableView(
                    "No Media to Watch",
                    systemImage: "play.rectangle"
                )
            }
        }
        .help("Playback follows the completed batch timeline; it is not streaming inference.")
    }

    private func positionText(for summary: SpeakerDiarizationMediaSummary) -> String {
        "\(SpeakerDiarizationTimeFormatter.format(currentTime)) / \(SpeakerDiarizationTimeFormatter.format(summary.durationSeconds))"
    }
}
