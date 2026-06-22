import SwiftUI

struct ChatterboxPipelineSection: View {
    let state: ChatterboxModelState

    private var inspection: ChatterboxModelInspection? {
        guard case .ready(let inspection) = state else {
            return nil
        }
        return inspection
    }

    var body: some View {
        Section("Native Pipeline") {
            ForEach(inspection?.assets ?? []) { asset in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: isReady(asset.stage)
                        ? "checkmark.circle.fill"
                        : "circle.dashed")
                        .foregroundStyle(isReady(asset.stage) ? .green : .secondary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.displayName)
                        Text(asset.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(asset.formattedSize)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            switch state {
            case .preparing:
                ProgressView("Loading the recipe contract")
            case .failed:
                Label("Pipeline details are unavailable", systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            case .notLoaded:
                Label("Recipe contract has not loaded", systemImage: "shippingbox")
                    .foregroundStyle(.secondary)
            case .ready:
                EmptyView()
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func isReady(_ stage: ChatterboxPipelineStage) -> Bool {
        inspection?.contractValidation.presentStages.contains(stage) == true
    }

    private var detail: String {
        switch state {
        case .notLoaded:
            "The app has not started validating the bundled recipe."
        case .preparing:
            "The app is verifying every bundled asset and function before enabling generation."
        case .ready(let inspection):
            inspection.contractValidation.isComplete
                ? "Text tokenization, autoregressive T3 decoding, S3Gen, and waveform synthesis all run locally."
                : "The recipe is incomplete; generation remains disabled."
        case .failed:
            "Model preparation failed, so the pipeline contract could not be verified."
        }
    }
}
