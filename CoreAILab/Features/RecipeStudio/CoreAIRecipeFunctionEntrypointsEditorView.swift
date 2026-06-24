import SwiftUI

struct CoreAIRecipeFunctionEntrypointsEditorView: View {
    @Bindable var workspace: CoreAIRecipeStudioWorkspaceModel

    var body: some View {
        Form {
            if workspace.recipe.functionEntrypoints.isEmpty {
                ContentUnavailableView(
                    "No Function Entrypoints",
                    systemImage: "function"
                )
                .help("Define at least one exported module method and its named contract.")
            }

            ForEach($workspace.recipe.functionEntrypoints) { $function in
                Section(function.name.isEmpty ? "Unnamed Function" : function.name) {
                    TextField("Function name", text: $function.name)
                        .coreAIRecipeIdentifierInput()
                    TextField("Module method", text: $function.moduleMethod)
                        .coreAIRecipeIdentifierInput()

                    CoreAIRecipeReferenceListEditorView(
                        title: "Inputs",
                        values: $function.inputNames,
                        choices: workspace.unambiguousExampleInputNames
                    )
                    CoreAIRecipeOutputListEditorView(values: $function.outputNames)
                    CoreAIRecipeReferenceListEditorView(
                        title: "State",
                        values: $function.stateNames,
                        choices: workspace.unambiguousStateNames
                    )

                    Button(
                        "Remove Function",
                        systemImage: "trash",
                        role: .destructive,
                        action: { removeFunction(id: function.id) }
                    )
                }
            }

            Section {
                Button(
                    "Add Function Entrypoint",
                    systemImage: "plus",
                    action: workspace.addFunctionEntrypoint
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Function Entrypoints")
    }

    private func removeFunction(id: String) {
        workspace.removeFunctionEntrypoint(id: id)
    }
}
