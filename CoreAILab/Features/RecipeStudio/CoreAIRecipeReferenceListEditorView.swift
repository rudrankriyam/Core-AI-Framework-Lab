import SwiftUI

struct CoreAIRecipeReferenceListEditorView: View {
    let title: String
    @Binding var values: [String]
    let choices: [String]

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading) {
                if values.isEmpty {
                    Text("None")
                        .foregroundStyle(.secondary)
                }
                ForEach(values, id: \.self) { value in
                    HStack {
                        Text(value)
                        Spacer()
                        Button(
                            "Remove \(value)",
                            systemImage: "minus.circle",
                            action: { remove(value) }
                        )
                        .labelStyle(.iconOnly)
                    }
                }
                Menu("Add \(title)", systemImage: "plus") {
                    ForEach(choices.filter { !values.contains($0) }, id: \.self) { value in
                        Button(value, action: { append(value) })
                    }
                }
                .disabled(choices.allSatisfy { values.contains($0) })
            }
        }
    }

    private func append(_ value: String) {
        guard !values.contains(value) else { return }
        values.append(value)
    }

    private func remove(_ value: String) {
        values.removeAll { $0 == value }
    }
}
