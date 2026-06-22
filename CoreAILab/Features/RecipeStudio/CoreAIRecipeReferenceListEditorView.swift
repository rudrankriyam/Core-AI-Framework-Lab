import SwiftUI

struct CoreAIRecipeReferenceListEditorView: View {
    let title: String
    @Binding var values: [String]
    let choices: [String]
    @State private var valueIDs: [UUID]

    init(
        title: String,
        values: Binding<[String]>,
        choices: [String]
    ) {
        self.title = title
        _values = values
        self.choices = choices
        _valueIDs = State(initialValue: values.wrappedValue.map { _ in UUID() })
    }

    var body: some View {
        let availableChoices = self.availableChoices

        GroupBox(title) {
            VStack(alignment: .leading) {
                if valueIDs.isEmpty {
                    Text("None")
                        .foregroundStyle(.secondary)
                }
                ForEach(valueIDs, id: \.self) { valueID in
                    if let value = value(for: valueID) {
                        HStack {
                            Text(value)
                            Spacer()
                            Button(
                                "Remove \(value)",
                                systemImage: "minus.circle",
                                action: { remove(id: valueID) }
                            )
                            .labelStyle(.iconOnly)
                        }
                    }
                }
                Menu("Add \(title)", systemImage: "plus") {
                    ForEach(availableChoices, id: \.self) { value in
                        Button(value, action: { append(value) })
                    }
                }
                .disabled(availableChoices.isEmpty)
            }
        }
    }

    private var availableChoices: [String] {
        Self.uniqueValues(choices).filter { !values.contains($0) }
    }

    static func uniqueValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func append(_ value: String) {
        guard !values.contains(value) else { return }
        values.append(value)
        valueIDs.append(UUID())
    }

    private func remove(id: UUID) {
        guard let index = valueIDs.firstIndex(of: id),
              values.indices.contains(index) else {
            return
        }
        values.remove(at: index)
        valueIDs.remove(at: index)
    }

    private func value(for id: UUID) -> String? {
        guard let index = valueIDs.firstIndex(of: id),
              values.indices.contains(index) else {
            return nil
        }
        return values[index]
    }
}
