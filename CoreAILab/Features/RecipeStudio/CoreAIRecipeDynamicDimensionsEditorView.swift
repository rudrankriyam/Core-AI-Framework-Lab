import SwiftUI

struct CoreAIRecipeDynamicDimensionsEditorView: View {
    @Bindable var workspace: CoreAIRecipeStudioWorkspaceModel

    var body: some View {
        Form {
            if workspace.recipe.dynamicDimensions.isEmpty {
                ContentUnavailableView(
                    "No Dynamic Dimensions",
                    systemImage: "arrow.left.and.right"
                )
                .help("Static example shapes remain unchanged until a bounded dynamic axis is added.")
            }

            ForEach($workspace.recipe.dynamicDimensions) { $dimension in
                Section(dimension.symbol.isEmpty ? "Unnamed Dimension" : dimension.symbol) {
                    Picker("Example input", selection: $dimension.inputName) {
                        ForEach(workspace.tensorInputNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    TextField("Axis", value: $dimension.axis, format: .number)
                        .coreAIRecipeIntegerInput()
                    TextField("Symbol", text: $dimension.symbol)
                        .coreAIRecipeIdentifierInput()
                    TextField("Minimum", value: $dimension.minimum, format: .number)
                        .coreAIRecipeIntegerInput()
                    TextField("Maximum", value: $dimension.maximum, format: .number)
                        .coreAIRecipeIntegerInput()

                    Button(
                        "Remove Dynamic Dimension",
                        systemImage: "trash",
                        role: .destructive,
                        action: { removeDimension(id: dimension.id) }
                    )
                }
            }

            Section {
                Button(
                    "Add Dynamic Dimension",
                    systemImage: "plus",
                    action: workspace.addDynamicDimension
                )
                .disabled(!workspace.canAddDynamicDimension)
                .help(
                    "Bounds are authoring constraints; they do not prove specialization or execution placement."
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Dynamic Dimensions")
    }

    private func removeDimension(id: String) {
        workspace.removeDynamicDimension(id: id)
    }
}
