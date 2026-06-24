import SwiftUI

struct SpeakerDiarizationAnalysisSection: View {
    private static let maximumContentWidth: CGFloat = 1_120
    private static let horizontalMargin: CGFloat = 64

    let waveform: SpeakerDiarizationWaveform?
    let result: SpeakerDiarizationResult?
    let playheadTime: Double
    let activeTurnID: Int?

    var body: some View {
        Section {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) {
                    SpeakerDiarizationTimelineView(
                        waveform: waveform,
                        result: result,
                        playheadTime: playheadTime
                    )
                    .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)

                    Divider()

                    SpeakerDiarizationResultsView(
                        result: result,
                        activeTurnID: activeTurnID
                    )
                    .frame(minWidth: 360, maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading) {
                    SpeakerDiarizationTimelineView(
                        waveform: waveform,
                        result: result,
                        playheadTime: playheadTime
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    Divider()

                    SpeakerDiarizationResultsView(
                        result: result,
                        activeTurnID: activeTurnID
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .containerRelativeFrame(.horizontal) { length, _ in
                min(
                    max(length - Self.horizontalMargin, 0),
                    Self.maximumContentWidth
                )
            }
        }
    }
}
