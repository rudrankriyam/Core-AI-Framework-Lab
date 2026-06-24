import SwiftUI

struct CoreAIRecipeStudioView: View {
    @State private var workspace: CoreAIRecipeStudioWorkspaceModel
    @SceneStorage("CoreAILab.recipeStudio.selectedPanel")
    private var selection: CoreAIRecipeStudioPanel?

    init(recipe: CoreAIRecipeAuthoringManifest = .starter) {
        _workspace = State(initialValue: CoreAIRecipeStudioWorkspaceModel(recipe: recipe))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Text(workspace.recipe.displayName)
                        .font(.headline)
                        .lineLimit(2)
                }

                Section("Authoring") {
                    CoreAIRecipeStudioPanelLink(panel: .source)
                    CoreAIRecipeStudioPanelLink(panel: .exampleInputs)
                    CoreAIRecipeStudioPanelLink(panel: .dynamicDimensions)
                    CoreAIRecipeStudioPanelLink(panel: .state)
                    CoreAIRecipeStudioPanelLink(panel: .externalization)
                    CoreAIRecipeStudioPanelLink(panel: .functions)
                }

                Section("Resolution") {
                    CoreAIRecipeStudioPanelLink(panel: .diagnostics)
                    CoreAIRecipeStudioPanelLink(panel: .rewrites)
                    CoreAIRecipeStudioPanelLink(panel: .generatedArtifacts)
                }

                Section("Composition") {
                    CoreAIRecipeStudioPanelLink(panel: .pipeline)
                }

                Section("Draft Status") {
                    Label(validationTitle, systemImage: validationSystemImage)
                        .foregroundStyle(validationStyle)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Recipe Studio")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            switch selection ?? .source {
            case .source:
                CoreAIRecipeSourceEditorView(workspace: workspace)
            case .exampleInputs:
                CoreAIRecipeExampleInputsEditorView(workspace: workspace)
            case .dynamicDimensions:
                CoreAIRecipeDynamicDimensionsEditorView(workspace: workspace)
            case .state:
                CoreAIRecipeStateEditorView(workspace: workspace)
            case .externalization:
                CoreAIRecipeExternalizationEditorView(workspace: workspace)
            case .functions:
                CoreAIRecipeFunctionEntrypointsEditorView(workspace: workspace)
            case .diagnostics:
                CoreAIUnsupportedOperationReportView(workspace: workspace)
            case .rewrites:
                CoreAIRecipeRewriteCatalogView()
            case .generatedArtifacts:
                CoreAIRecipeGeneratedArtifactsView(workspace: workspace)
            case .pipeline:
                CoreAIPipelineStudioView(workspace: workspace)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var validationTitle: String {
        let count = workspace.validationIssues.count
        if count == 0 {
            return "Structurally valid"
        } else if count == 1 {
            return "1 validation issue"
        } else {
            return "\(count) validation issues"
        }
    }

    private var validationSystemImage: String {
        workspace.validationIssues.isEmpty
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
    }

    private var validationStyle: AnyShapeStyle {
        workspace.validationIssues.isEmpty
            ? AnyShapeStyle(.green)
            : AnyShapeStyle(.orange)
    }
}

#Preview {
    CoreAIRecipeStudioView()
}
