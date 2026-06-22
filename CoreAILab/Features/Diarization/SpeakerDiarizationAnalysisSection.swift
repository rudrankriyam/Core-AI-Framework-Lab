import SwiftUI

enum SpeakerDiarizationAnalysisLayout: Equatable {
    case stacked
    case sideBySide

    static let minimumSideBySideWidth: CGFloat = 880

    init(contentWidth: CGFloat) {
        self = contentWidth >= Self.minimumSideBySideWidth ? .sideBySide : .stacked
    }
}

struct SpeakerDiarizationAnalysisSection: View {
    private static let maximumContentWidth: CGFloat = 1_120
    private static let horizontalMargin: CGFloat = 64

    let availableWidth: CGFloat
    let waveform: SpeakerDiarizationWaveform?
    let result: SpeakerDiarizationResult?
    let playheadTime: Double
    let activeTurnID: Int?

    private var contentWidth: CGFloat {
        min(
            max(availableWidth - Self.horizontalMargin, 0),
            Self.maximumContentWidth
        )
    }

    private var layout: SpeakerDiarizationAnalysisLayout {
        SpeakerDiarizationAnalysisLayout(contentWidth: contentWidth)
    }

    var body: some View {
        Section {
            Group {
                if layout == .sideBySide {
                    HStack(alignment: .top, spacing: 20) {
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
                } else {
                    VStack(alignment: .leading, spacing: 20) {
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
            }
            .frame(width: contentWidth, alignment: .topLeading)
        }
    }
}
