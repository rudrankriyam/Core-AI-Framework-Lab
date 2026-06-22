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
            Label(statusMessage, systemImage: isBusy ? "hourglass" : "waveform.badge.mic")
                .foregroundStyle(isBusy ? .primary : .secondary)
        } header: {
            Label("Speaker Diarization Lab", systemImage: "person.wave.2")
        } footer: {
            Text("The bundled CAM++ asset is Apache-2.0. This experimental batch engine assigns anonymous labels, not real identities, and energy segmentation does not detect overlapping speakers.")
        }
    }
}
