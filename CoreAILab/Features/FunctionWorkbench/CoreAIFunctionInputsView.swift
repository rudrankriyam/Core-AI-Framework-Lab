import SwiftUI

struct CoreAIFunctionInputsView: View {
    let drafts: [CoreAIFunctionInputDraft]
    let isDisabled: Bool

    var body: some View {
        Section {
            if drafts.isEmpty {
                Label("No Generated Inputs", systemImage: "minus.circle")
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
