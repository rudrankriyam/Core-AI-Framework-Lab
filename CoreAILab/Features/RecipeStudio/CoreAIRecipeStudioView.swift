import SwiftUI

struct CoreAIRecipeStudioView: View {
    @State private var workspace: CoreAIRecipeStudioWorkspaceModel
    @State private var selection: CoreAIRecipeStudioPanel? = .source

    init(recipe: CoreAIRecipeAuthoringManifest = .starter) {
        _workspace = State(initialValue: CoreAIRecipeStudioWorkspaceModel(recipe: recipe))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
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
                    LabeledContent("Validation issues") {
                        Text(workspace.validationIssues.count, format: .number)
                    }
                }
            }
            .navigationTitle("Recipe Studio")
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
}

#Preview {
    CoreAIRecipeStudioView()
}
