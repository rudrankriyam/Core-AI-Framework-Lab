import SwiftUI

struct CoreAIRecipeStateEditorView: View {
    @Bindable var workspace: CoreAIRecipeStudioWorkspaceModel

    var body: some View {
        Form {
            if workspace.recipe.stateBindings.isEmpty {
                ContentUnavailableView(
                    "No Explicit State",
                    systemImage: "memorychip"
                )
                .help("Add state only when exported functions expose named input and output bindings.")
            }

            ForEach($workspace.recipe.stateBindings) { $state in
                Section(state.name.isEmpty ? "Unnamed State" : state.name) {
                    TextField("State name", text: stateNameBinding(id: state.id))
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

    private func stateNameBinding(id: String) -> Binding<String> {
        Binding(
            get: {
                workspace.recipe.stateBindings.first { $0.id == id }?.name ?? ""
            },
            set: { workspace.renameStateBinding(id: id, to: $0) }
        )
    }
}
