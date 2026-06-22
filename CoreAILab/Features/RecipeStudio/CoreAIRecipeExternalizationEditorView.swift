import SwiftUI

struct CoreAIRecipeExternalizationEditorView: View {
    @Bindable var workspace: CoreAIRecipeStudioWorkspaceModel

    var body: some View {
        Form {
            if workspace.recipe.externalizationRules.isEmpty {
                ContentUnavailableView(
                    "No Externalization Rules",
                    systemImage: "externaldrive",
                    description: Text("Weights remain under the converter's default policy until a module rule is added.")
                )
            }

            ForEach($workspace.recipe.externalizationRules) { $rule in
                Section(rule.resourceName.isEmpty ? "Unnamed Resource" : rule.resourceName) {
                    TextField("Module path", text: $rule.modulePath)
                        .coreAIRecipeIdentifierInput()
                    Picker("Strategy", selection: $rule.strategy) {
                        ForEach(CoreAIRecipeExternalizationRule.Strategy.allCases, id: \.self) { strategy in
                            Text(strategy.title).tag(strategy)
                        }
                    }
                    TextField("Minimum bytes", value: $rule.minimumBytes, format: .number)
                        .coreAIRecipeIntegerInput()
                    TextField("Resource name", text: $rule.resourceName)
                        .coreAIRecipeIdentifierInput()

                    Button(
                        "Remove Rule",
                        systemImage: "trash",
                        role: .destructive,
                        action: { removeRule(id: rule.id) }
                    )
                }
            }

            Section {
                Button(
                    "Add Externalization Rule",
                    systemImage: "plus",
                    action: workspace.addExternalizationRule
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Externalization")
    }

    private func removeRule(id: String) {
        workspace.removeExternalizationRule(id: id)
    }
}
