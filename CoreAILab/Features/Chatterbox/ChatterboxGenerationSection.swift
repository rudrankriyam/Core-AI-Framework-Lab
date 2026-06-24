import SwiftUI

struct ChatterboxGenerationSection: View {
    let canGenerate: Bool
    let isWorking: Bool
    let workingActionTitle: String
    let statusMessage: String
    let result: ChatterboxGenerationResult?
    let isPlaying: Bool
    let generateAction: () -> Void
    let playbackAction: () -> Void

    var body: some View {
        Section {
            Button(action: generateAction) {
                Label {
                    Text(isWorking ? workingActionTitle : "Generate Speech")
                } icon: {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "play.circle.fill")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canGenerate)

            if isWorking {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            if let result {
                Button(
                    isPlaying ? "Stop Playback" : "Play Generated Speech",
                    systemImage: isPlaying ? "stop.fill" : "speaker.wave.3.fill",
                    action: playbackAction
                )

                LabeledContent(
                    "Generation time",
                    value: "\(result.elapsedTime.formatted(.number.precision(.fractionLength(2)))) seconds"
                )
                LabeledContent(
                    "Audio duration",
                    value: "\(result.audioDuration.formatted(.number.precision(.fractionLength(2)))) seconds"
                )
                LabeledContent(
                    "Real-time factor",
                    value: result.realTimeFactor,
                    format: .number.precision(.fractionLength(2))
                )
                LabeledContent(
                    "Speech tokens",
                    value: result.generatedTokenCount,
                    format: .number
                )

                ShareLink(
                    item: result.audioURL,
                    preview: SharePreview("Chatterbox Core AI audio")
                ) {
                    Label("Share Generated Audio", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Label("Generate & Playback", systemImage: "speaker.wave.3")
        } footer: {
            Text("The first launch specializes the bundled graphs. Later runs reuse Core AI's persistent cache.")
        }
    }
}
