import SwiftUI

struct CoreAIRecipeGeneratedArtifactsView: View {
    @Bindable var workspace: CoreAIRecipeStudioWorkspaceModel

    var body: some View {
        Form {
            if workspace.generatedArtifacts.isEmpty {
                ContentUnavailableView(
                    "No Generated Stubs",
                    systemImage: "doc.badge.gearshape"
                )
                .help("Generate stubs from an attributed unsupported-operation finding.")
            }

            ForEach(workspace.generatedArtifacts) { artifact in
                Section(artifact.kind.title) {
                    Text(artifact.relativePath)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    ScrollView(.horizontal) {
                        Text(artifact.contents)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Safety") {
                Text(
                    "Custom-lowering stubs raise NotImplementedError and Metal stubs contain a compile-time error. Neither artifact can silently behave like a completed rewrite."
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Generated Stubs")
    }
}
