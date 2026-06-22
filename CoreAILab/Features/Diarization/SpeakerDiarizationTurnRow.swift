import SwiftUI

struct SpeakerDiarizationTurnRow: View {
    let turn: SpeakerDiarizationTurn
    let isActive: Bool

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing) {
                Text(timeRange)
                    .monospacedDigit()
                Text(confidence)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } label: {
            HStack {
                Label(
                    turn.speakerName,
                    systemImage: isActive ? "speaker.wave.3.fill" : "person.wave.2"
                )
                if isActive {
                    Text("Now")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.18), in: .capsule)
                }
            }
        }
        .accessibilityHint(isActive ? "Currently under the watcher playhead." : "")
    }

    private var timeRange: String {
        "\(SpeakerDiarizationTimeFormatter.format(turn.startTime)) - \(SpeakerDiarizationTimeFormatter.format(turn.endTime))"
    }

    private var confidence: String {
        "Stub confidence \(turn.confidence.formatted(.percent.precision(.fractionLength(0))))"
    }
}
