import SwiftUI

struct SpeakerDiarizationTimelineView: View {
    let waveform: SpeakerDiarizationWaveform?
    let result: SpeakerDiarizationResult?
    let playheadTime: Double

    var body: some View {
        Section("Timeline") {
            if let waveform {
                SpeakerDiarizationWaveformView(
                    waveform: waveform,
                    turns: result?.turns ?? [],
                    playheadTime: playheadTime
                )
                .frame(minHeight: 150)

                LabeledContent(
                    "Playhead",
                    value: SpeakerDiarizationTimeFormatter.format(playheadTime)
                )
                LabeledContent(
                    "Duration",
                    value: SpeakerDiarizationTimeFormatter.format(waveform.durationSeconds)
                )
                LabeledContent(
                    "Turns",
                    value: (result?.turns.count ?? 0).formatted()
                )
            } else {
                ContentUnavailableView(
                    "No Media Selected",
                    systemImage: "waveform",
                    description: Text("Choose an audio or video file to build the first timeline.")
                )
            }
        }
    }
}
