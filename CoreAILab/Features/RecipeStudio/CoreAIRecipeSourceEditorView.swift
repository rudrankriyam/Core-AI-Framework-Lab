import SwiftUI

struct CoreAIRecipeSourceEditorView: View {
    @Bindable var workspace: CoreAIRecipeStudioWorkspaceModel

    var body: some View {
        Form {
            Section("Recipe") {
                TextField("Display name", text: $workspace.recipe.displayName)
                TextField("Recipe ID", text: $workspace.recipe.id)
                    .coreAIRecipeIdentifierInput()
            }

            Section {
                Picker("Source kind", selection: $workspace.recipe.source.kind) {
                    ForEach(CoreAIRecipeSource.Kind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                TextField("Path or repository ID", text: $workspace.recipe.source.location)
                    .coreAIRecipeIdentifierInput()
                TextField("Pinned revision", text: $workspace.recipe.source.revision)
                    .coreAIRecipeIdentifierInput()
            } header: {
                Text("PyTorch Source")
            } footer: {
                Text("A blank revision is allowed while drafting, but a reproducible conversion should pin one before execution.")
            }

            Section("Module") {
                TextField("Python module path", text: $workspace.recipe.module.modulePath)
                    .coreAIRecipeIdentifierInput()
                TextField("Module type", text: $workspace.recipe.module.typeName)
                    .coreAIRecipeIdentifierInput()
                TextField("Factory function", text: $workspace.recipe.module.factoryFunction)
                    .coreAIRecipeIdentifierInput()
                TextField("Checkpoint path", text: $workspace.recipe.module.checkpointPath)
                    .coreAIRecipeIdentifierInput()
            }

            Section("Validation") {
                CoreAIRecipeValidationIssuesView(issues: workspace.validationIssues)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Source & Module")
    }
}
