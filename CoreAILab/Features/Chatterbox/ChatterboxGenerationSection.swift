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
            Button(
                "Generate speech",
                systemImage: "play.circle.fill",
                action: generateAction
            )
            .buttonStyle(.borderedProminent)
            .disabled(!canGenerate)

            if isWorking {
                ProgressView(statusMessage)
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
                    Label("Share generated audio", systemImage: "square.and.arrow.up")
                }
            }
        } footer: {
            Text("The first launch specializes the bundled graphs. Later runs reuse Core AI's persistent cache.")
        }
    }
}
