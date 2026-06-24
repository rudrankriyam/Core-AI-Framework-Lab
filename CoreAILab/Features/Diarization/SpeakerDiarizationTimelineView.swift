import SwiftUI

struct SpeakerDiarizationTimelineView: View {
    let waveform: SpeakerDiarizationWaveform?
    let result: SpeakerDiarizationResult?
    let playheadTime: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if let waveform {
                SpeakerDiarizationWaveformView(
                    waveform: waveform,
                    turns: result?.turns ?? [],
                    playheadTime: playheadTime
                )
                .frame(minHeight: 150)

                VStack(spacing: 0) {
                    LabeledContent(
                        "Playhead",
                        value: SpeakerDiarizationTimeFormatter.format(playheadTime)
                    )
                    .padding(.vertical, 6)

                    Divider()

                    LabeledContent(
                        "Duration",
                        value: SpeakerDiarizationTimeFormatter.format(waveform.durationSeconds)
                    )
                    .padding(.vertical, 6)

                    Divider()

                    LabeledContent(
                        "Turns",
                        value: (result?.turns.count ?? 0).formatted()
                    )
                    .padding(.vertical, 6)
                }
            } else {
                ContentUnavailableView(
                    "No Media Selected",
                    systemImage: "waveform"
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
    }
}
