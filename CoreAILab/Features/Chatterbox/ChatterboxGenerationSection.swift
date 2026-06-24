import SwiftUI

struct ChatterboxGenerationSection: View {
    let canGenerate: Bool
    let isWorking: Bool
    let statusMessage: String
    let result: ChatterboxGenerationResult?
    let isPlaying: Bool
    let generateAction: () -> Void
    let playbackAction: () -> Void

    var body: some View {
        Section {
            Button(action: generateAction) {
                Label {
                    Text(isWorking ? "Generating Speech…" : "Generate Speech")
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
                    isPlaying ? "Stop playback" : "Play generated speech",
                    systemImage: isPlaying ? "stop.fill" : "speaker.wave.3.fill",
                    action: playbackAction
                )

                LabeledContent(
                    "Generation",
                    value: result.elapsedTime,
                    format: .number.precision(.fractionLength(2))
                )
                LabeledContent(
                    "Audio",
                    value: result.audioDuration,
                    format: .number.precision(.fractionLength(2))
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
