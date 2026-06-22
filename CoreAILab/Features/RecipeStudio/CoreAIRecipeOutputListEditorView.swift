import SwiftUI

struct CoreAIRecipeOutputListEditorView: View {
    @Binding var values: [String]

    var body: some View {
        GroupBox("Outputs") {
            VStack(alignment: .leading) {
                ForEach(values.indices, id: \.self) { index in
                    HStack {
                        TextField("Output name", text: $values[index])
                            .coreAIRecipeIdentifierInput()
                        Button(
                            "Remove Output",
                            systemImage: "minus.circle",
                            action: { remove(at: index) }
                        )
                        .labelStyle(.iconOnly)
                    }
                }
                Button("Add Output", systemImage: "plus", action: append)
            }
        }
    }

    private func append() {
        values.append("output_\(values.count + 1)")
    }

    private func remove(at index: Int) {
        guard values.indices.contains(index) else { return }
        values.remove(at: index)
    }
}
