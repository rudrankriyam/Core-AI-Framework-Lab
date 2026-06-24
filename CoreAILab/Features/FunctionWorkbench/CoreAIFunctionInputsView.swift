import SwiftUI

struct CoreAIFunctionInputsView: View {
    let drafts: [CoreAIFunctionInputDraft]
    let isDisabled: Bool

    var body: some View {
        Section {
            if drafts.isEmpty {
                Text("This function has no generated tensor inputs.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(drafts, id: \.name) { draft in
                    CoreAIFunctionInputDraftView(
                        draft: draft,
                        isDisabled: isDisabled
                    )
                }
            }
        } header: {
            Label("Generated Inputs", systemImage: "slider.horizontal.3")
        }
    }
}
