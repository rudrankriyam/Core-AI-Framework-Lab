import SwiftUI

struct CoreAIFunctionInputDraftView: View {
    @Bindable var draft: CoreAIFunctionInputDraft
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(draft.name) {
                Text(draft.tensor.scalarTypeName)
                    .font(.body.monospaced())
            }

            if draft.tensor.hasDynamicShape {
                TextField("Shape", text: $draft.shapeText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Shape for \(draft.name)")
            } else {
                LabeledContent("Shape", value: draft.shapeText)
            }

            Picker("Input values", selection: $draft.generator) {
                ForEach(CoreAIFunctionInputGenerator.allCases) { generator in
                    Text(generator.title).tag(generator)
                }
            }

            if draft.generator == .random {
                TextField("Seed", value: $draft.seed, format: .number)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .disabled(isDisabled)
        .padding(.vertical, 4)
    }
}
