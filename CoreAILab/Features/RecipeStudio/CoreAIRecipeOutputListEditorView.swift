import SwiftUI

struct CoreAIRecipeOutputListEditorView: View {
    @Binding var values: [String]
    @State private var outputIDs: [UUID]

    init(values: Binding<[String]>) {
        _values = values
        _outputIDs = State(initialValue: values.wrappedValue.map { _ in UUID() })
    }

    var body: some View {
        GroupBox("Outputs") {
            VStack(alignment: .leading) {
                ForEach(outputIDs, id: \.self) { outputID in
                    if let value = outputBinding(for: outputID) {
                        HStack {
                            TextField("Output name", text: value)
                                .coreAIRecipeIdentifierInput()
                            Button(
                                "Remove Output",
                                systemImage: "minus.circle",
                                action: { remove(id: outputID) }
                            )
                            .labelStyle(.iconOnly)
                        }
                    }
                }
                Button("Add Output", systemImage: "plus", action: append)
            }
        }
    }

    private func append() {
        values.append(Self.nextOutputName(in: values))
        outputIDs.append(UUID())
    }

    static func nextOutputName(in values: [String]) -> String {
        let existing = Set(values)
        var index = values.count + 1
        while existing.contains("output_\(index)") {
            index += 1
        }
        return "output_\(index)"
    }

    private func remove(id: UUID) {
        guard let index = outputIDs.firstIndex(of: id),
              values.indices.contains(index) else {
            return
        }
        values.remove(at: index)
        outputIDs.remove(at: index)
    }

    private func outputBinding(for id: UUID) -> Binding<String>? {
        guard let index = outputIDs.firstIndex(of: id),
              values.indices.contains(index) else {
            return nil
        }
        return $values[index]
    }
}
