import SwiftUI

struct AppleAudioTranscriptionResultView: View {
    let result: AppleAudioTranscriptionResult?

    var body: some View {
        Section {
            if let result {
                if result.transcript.isEmpty {
                    ContentUnavailableView(
                        "No Speech Detected",
                        systemImage: "waveform.slash",
                        description: Text("Wav2Vec2 returned only blank CTC tokens.")
                    )
                } else {
                    Text(result.transcript)
                        .font(.title3)
                        .textSelection(.enabled)
                }
                LabeledContent(
                    "Audio",
                    value: "\(result.audioDurationSeconds.formatted(.number.precision(.fractionLength(2)))) seconds"
                )
                LabeledContent(
                    "Inference",
                    value: "\(result.inferenceDurationSeconds.formatted(.number.precision(.fractionLength(2)))) seconds"
                )
            } else {
                ContentUnavailableView(
                    "No Transcript Yet",
                    systemImage: "captions.bubble"
                )
            }
        } header: {
            Label("Transcript", systemImage: "captions.bubble")
        }
    }
}
