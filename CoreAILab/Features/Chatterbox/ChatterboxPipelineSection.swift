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
        Section {
            ForEach(inspection?.assets ?? []) { asset in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: isReady(asset.stage)
                        ? "checkmark.circle.fill"
                        : "circle.dashed")
                        .foregroundStyle(isReady(asset.stage) ? .green : .secondary)
                        .accessibilityHidden(true)

                    Text(asset.displayName)
                        .help(asset.detail)

                    Spacer()

                    Text(asset.formattedSize)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            switch state {
            case .preparing:
                ProgressView("Loading the recipe contract…")
            case .failed:
                Label("Pipeline details are unavailable", systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            case .notLoaded:
                Label("Recipe contract has not loaded", systemImage: "shippingbox")
                    .foregroundStyle(.secondary)
            case .ready:
                EmptyView()
            }

        } header: {
            Label("Native Pipeline", systemImage: "point.3.connected.trianglepath.dotted")
        }
    }

    private func isReady(_ stage: ChatterboxPipelineStage) -> Bool {
        inspection?.contractValidation.presentStages.contains(stage) == true
    }

}
