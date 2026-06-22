import SwiftUI

struct SpeakerDiarizationStatusSection: View {
    let summary: SpeakerDiarizationMediaSummary?
    let statusMessage: String
    let isBusy: Bool

    var body: some View {
        Section {
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
            Text("This slice uses a deterministic stub engine for UI iteration. It identifies anonymous speaker turns, not real identities.")
        }
    }
}
