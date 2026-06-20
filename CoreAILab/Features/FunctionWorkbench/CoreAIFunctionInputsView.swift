import SwiftUI

struct CoreAIFunctionInputsView: View {
    let drafts: [CoreAIFunctionInputDraft]
    let isDisabled: Bool

    var body: some View {
        Section("Generated Inputs") {
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
        }
    }
}
