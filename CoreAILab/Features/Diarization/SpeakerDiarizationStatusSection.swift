import SwiftUI

struct SpeakerDiarizationStatusSection: View {
    let modelInfo: SpeakerDiarizationModelInfo?
    let summary: SpeakerDiarizationMediaSummary?
    let statusMessage: String
    let isBusy: Bool

    var body: some View {
        Section {
            LabeledContent("CAM++ model", value: modelInfo?.assetName ?? "Not loaded")
            if let modelInfo {
                LabeledContent(
                    "Contract",
                    value: "1 × \(modelInfo.frameCount) × \(modelInfo.featureBinCount) → \(modelInfo.embeddingDimension)"
                )
                LabeledContent("Precision", value: modelInfo.scalarTypeName)
            }
            LabeledContent("Media", value: summary?.fileName ?? "Not selected")
            if let summary {
                LabeledContent("Type", value: summary.kind.rawValue.capitalized)
                LabeledContent(
                    "Duration",
                    value: SpeakerDiarizationTimeFormatter.format(summary.durationSeconds)
                )
                LabeledContent("Channels", value: summary.channelCount.formatted())
                if summary.sampleRate > 0 {
                    LabeledContent(
                        "Sample rate",
                        value: "\(Int(summary.sampleRate).formatted()) Hz"
                    )
                }
            }
            if isBusy {
                ProgressView(statusMessage)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        } header: {
            Label("Speaker Diarization", systemImage: "person.wave.2")
        }
        .help(
            "\(statusMessage) The Apache-2.0 CAM++ engine uses anonymous labels and does not detect overlapping speakers."
        )
    }
}
