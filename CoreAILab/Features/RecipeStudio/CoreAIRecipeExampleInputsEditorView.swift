import SwiftUI

struct CoreAIRecipeExampleInputsEditorView: View {
    @Bindable var workspace: CoreAIRecipeStudioWorkspaceModel

    var body: some View {
        Form {
            if workspace.recipe.exampleInputs.isEmpty {
                ContentUnavailableView(
                    "No Example Inputs",
                    systemImage: "square.and.pencil",
                    description: Text("Add the concrete arguments used to export and validate this recipe.")
                )
            }

            ForEach($workspace.recipe.exampleInputs) { $input in
                Section(input.name.isEmpty ? "Unnamed Input" : input.name) {
                    TextField("Name", text: $input.name)
                        .coreAIRecipeIdentifierInput()
                    Picker("Value kind", selection: $input.kind) {
                        ForEach(CoreAIRecipeExampleInput.ValueKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }

                    if [.tensor, .scalar].contains(input.kind) {
                        TextField("Scalar type", text: $input.scalarType)
                            .coreAIRecipeIdentifierInput()
                    }

                    if input.kind == .tensor {
                        LabeledContent("Shape") {
                            VStack(alignment: .trailing) {
                                ForEach(input.shape.indices, id: \.self) { axis in
                                    HStack {
                                        Text("Axis \(axis)")
                                        TextField(
                                            "Size",
                                            value: $input.shape[axis],
                                            format: .number
                                        )
                                        .coreAIRecipeIntegerInput()
                                        .multilineTextAlignment(.trailing)
                                    }
                                }
                                Button("Add Axis", systemImage: "plus", action: {
                                    addAxis(to: $input)
                                })
                            }
                        }
                        TextField("Fixture path", text: $input.fixturePath)
                            .coreAIRecipeIdentifierInput()
                    } else {
                        TextField("Literal value", text: $input.literalValue, axis: .vertical)
                            .lineLimit(2...4)
                    }

                    Button(
                        "Remove Input",
                        systemImage: "trash",
                        role: .destructive,
                        action: { removeInput(id: input.id) }
                    )
                }
            }

            Section {
                Button("Add Example Input", systemImage: "plus", action: workspace.addExampleInput)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Example Inputs")
    }

    private func addAxis(to input: Binding<CoreAIRecipeExampleInput>) {
        input.wrappedValue.shape.append(1)
    }

    private func removeInput(id: String) {
        workspace.removeExampleInput(id: id)
    }
}
