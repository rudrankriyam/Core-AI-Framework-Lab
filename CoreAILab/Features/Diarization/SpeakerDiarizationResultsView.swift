import SwiftUI

struct SpeakerDiarizationResultsView: View {
    let result: SpeakerDiarizationResult?
    let activeTurnID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diarization Results")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if let result {
                let speakerNames = result.speakerNames

                VStack(spacing: 0) {
                    LabeledContent("Engine", value: result.engineName)
                        .padding(.vertical, 6)

                    Divider()

                    LabeledContent(
                        "Speakers",
                        value: speakerNames.isEmpty
                            ? "None detected"
                            : speakerNames.joined(separator: ", ")
                    )
                        .padding(.vertical, 6)

                    if let evidence = result.evidence {
                        Divider()
                        LabeledContent("Model", value: evidence.modelName)
                            .padding(.vertical, 6)

                        Divider()
                        LabeledContent(
                            "Speech / windows",
                            value: "\(evidence.speechRegionCount) / \(evidence.analysisWindowCount)"
                        )
                        .padding(.vertical, 6)

                        Divider()
                        LabeledContent(
                            "Audio decode",
                            value: evidence.decodeSeconds.formatted(
                                .number.precision(.fractionLength(3))
                            ) + " s"
                        )
                        .padding(.vertical, 6)

                        Divider()
                        LabeledContent(
                            "Core AI inference",
                            value: evidence.inferenceSeconds.formatted(
                                .number.precision(.fractionLength(3))
                            ) + " s"
                        )
                        .padding(.vertical, 6)

                        Divider()
                        LabeledContent(
                            "Total analysis",
                            value: evidence.totalSeconds.formatted(
                                .number.precision(.fractionLength(3))
                            ) + " s"
                        )
                        .padding(.vertical, 6)
                    }

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
                    description: Text("Choose media, then run the bundled CAM++ diarizer.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
    }
}
