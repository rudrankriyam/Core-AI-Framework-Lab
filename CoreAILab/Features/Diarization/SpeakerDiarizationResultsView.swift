import SwiftUI

struct SpeakerDiarizationResultsView: View {
    let result: SpeakerDiarizationResult?
    let activeTurnID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stub Results")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if let result {
                VStack(spacing: 0) {
                    LabeledContent("Engine", value: result.engineName)
                        .padding(.vertical, 6)

                    Divider()

                    LabeledContent("Speakers", value: result.speakerNames.joined(separator: ", "))
                        .padding(.vertical, 6)

                    ForEach(result.turns) { turn in
                        Divider()
                        SpeakerDiarizationTurnRow(
                            turn: turn,
                            isActive: turn.id == activeTurnID
                        )
                        .padding(.vertical, 8)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Speaker Turns Yet",
                    systemImage: "person.2.slash",
                    description: Text("Run the stub engine after import to preview the diarization timeline.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
    }
}
