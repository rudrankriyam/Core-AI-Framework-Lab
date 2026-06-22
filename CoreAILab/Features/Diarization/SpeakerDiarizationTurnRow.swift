import SwiftUI

struct SpeakerDiarizationTurnRow: View {
    let turn: SpeakerDiarizationTurn
    let isActive: Bool

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing) {
                Text(timeRange)
                    .monospacedDigit()
                Text(clusterEvidence)
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

    private var clusterEvidence: String {
        guard let similarity = turn.clusterSimilarity else {
            return "New cluster"
        }
        return "Cluster cosine \(similarity.formatted(.number.precision(.fractionLength(3))))"
    }
}
