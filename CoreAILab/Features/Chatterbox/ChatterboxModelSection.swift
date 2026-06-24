import SwiftUI

struct ChatterboxModelSection: View {
    let state: ChatterboxModelState

    var body: some View {
        Section {
            Label(state.title, systemImage: state.systemImage)

            Text(state.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if case .ready(let inspection) = state {
                LabeledContent("Model bundle", value: inspection.formattedTotalSize)
                LabeledContent("Assets", value: inspection.assets.count, format: .number)
                LabeledContent("Functions", value: inspection.totalFunctionCount, format: .number)
                LabeledContent("Architecture", value: inspection.deviceArchitectureName)

                if !inspection.author.isEmpty {
                    LabeledContent("Author", value: inspection.author)
                }
            }
        } header: {
            Label("Bundled Core AI Model", systemImage: "shippingbox")
        }
    }
}
