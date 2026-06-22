import SwiftUI

struct CoreAIRecipeStateEditorView: View {
    @Bindable var workspace: CoreAIRecipeStudioWorkspaceModel

    var body: some View {
        Form {
            if workspace.recipe.stateBindings.isEmpty {
                ContentUnavailableView(
                    "No Explicit State",
                    systemImage: "memorychip",
                    description: Text("Add state only when the exported functions expose named input and output bindings.")
                )
            }

            ForEach($workspace.recipe.stateBindings) { $state in
                Section(state.name.isEmpty ? "Unnamed State" : state.name) {
                    TextField("State name", text: $state.name)
                        .coreAIRecipeIdentifierInput()
                    TextField("Input binding", text: $state.inputName)
                        .coreAIRecipeIdentifierInput()
                    TextField("Output binding", text: $state.outputName)
                        .coreAIRecipeIdentifierInput()
                    TextField("Initial-value reference", text: $state.initialValueReference)
                        .coreAIRecipeIdentifierInput()
                    Toggle("Mutable across calls", isOn: $state.isMutable)

                    Button(
                        "Remove State",
                        systemImage: "trash",
                        role: .destructive,
                        action: { removeState(id: state.id) }
                    )
                }
            }

            Section {
                Button("Add State", systemImage: "plus", action: workspace.addStateBinding)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("State")
    }

    private func removeState(id: String) {
        workspace.removeStateBinding(id: id)
    }
}
