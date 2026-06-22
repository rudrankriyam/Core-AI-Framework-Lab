import SwiftUI

struct SpeakerDiarizationImportSection: View {
    let canRunDiarization: Bool
    let isBusy: Bool
    let importModelAction: () -> Void
    let importMediaAction: () -> Void
    let runAction: () -> Void

    var body: some View {
        Section("Inputs") {
            ViewThatFits(in: .horizontal) {
                HStack {
                    controls
                }

                VStack(alignment: .leading) {
                    controls
                }
            }

            Text("The batch path decodes 16 kHz mono audio, finds energy-based speech regions, runs CAM++ through Core AI with six-second context, then clusters embeddings by cosine similarity.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        Button("Import CAM++", systemImage: "shippingbox", action: importModelAction)
            .disabled(isBusy)
        Button("Choose Audio or Video", systemImage: "waveform", action: importMediaAction)
            .disabled(isBusy)
        Button("Run Diarization", systemImage: "person.2.wave.2", action: runAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canRunDiarization)
    }
}
