import SwiftUI

struct ChatterboxPipelineSection: View {
    let inspection: ChatterboxModelInspection?

    var body: some View {
        Section("Native Pipeline") {
            ForEach(ChatterboxPipelineStage.allCases) { stage in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: isReady(stage)
                        ? "checkmark.circle.fill"
                        : "circle.dashed")
                        .foregroundStyle(isReady(stage) ? .green : .secondary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.title)
                        Text(stage.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let asset = inspection?.assets.first(
                        where: { $0.stage == stage }
                    ) {
                        Text(asset.formattedSize)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Text(inspection?.contractValidation.isComplete == true
                ? "Text tokenization, autoregressive T3 decoding, S3Gen, and waveform synthesis all run locally."
                : "The app verifies every bundled asset and function before enabling generation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func isReady(_ stage: ChatterboxPipelineStage) -> Bool {
        inspection?.contractValidation.presentStages.contains(stage) == true
    }
}
