import SwiftUI

struct SpeakerDiarizationResultsView: View {
    let result: SpeakerDiarizationResult?
    let activeTurnID: Int?

    var body: some View {
        Section("Stub Results") {
            if let result {
                LabeledContent("Engine", value: result.engineName)
                LabeledContent("Speakers", value: result.speakerNames.joined(separator: ", "))
                ForEach(result.turns) { turn in
                    SpeakerDiarizationTurnRow(
                        turn: turn,
                        isActive: turn.id == activeTurnID
                    )
                }
            } else {
                ContentUnavailableView(
                    "No Speaker Turns Yet",
                    systemImage: "person.2.slash",
                    description: Text("Run the stub engine after import to preview the diarization timeline.")
                )
            }
        }
    }
}
