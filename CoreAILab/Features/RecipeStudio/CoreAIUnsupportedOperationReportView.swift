import SwiftUI

struct CoreAIUnsupportedOperationReportView: View {
    @Bindable var workspace: CoreAIRecipeStudioWorkspaceModel

    var body: some View {
        Form {
            if workspace.recipe.unsupportedOperations.isEmpty {
                ContentUnavailableView(
                    "No Unsupported Operations Reported",
                    systemImage: "checkmark.circle",
                    description: Text("This means the draft has no imported findings; it does not prove that export will succeed.")
                )
            }

            ForEach(workspace.recipe.unsupportedOperations) { finding in
                Section(finding.operatorName) {
                    LabeledContent("Severity", value: finding.severity.title)
                    LabeledContent("Module", value: finding.modulePath)
                    LabeledContent("Source") {
                        Text("\(finding.sourceFile):\(finding.sourceLine)")
                            .textSelection(.enabled)
                    }
                    Text(finding.message)

                    if !finding.exampleShapes.isEmpty {
                        LabeledContent("Example shapes") {
                            VStack(alignment: .trailing) {
                                ForEach(finding.exampleShapes.indices, id: \.self) { index in
                                    Text(finding.exampleShapes[index])
                                        .monospaced()
                                }
                            }
                        }
                    }

                    if let rewrite = CoreAIRecipeRewriteCatalog.rewrite(
                        id: finding.suggestedRewriteID
                    ) {
                        LabeledContent("Known rewrite", value: rewrite.title)
                        Text(rewrite.summary)
                            .foregroundStyle(.secondary)
                    }

                    Button(
                        "Generate Failing Stubs",
                        systemImage: "doc.badge.gearshape",
                        action: { generateStubs(for: finding) }
                    )
                }
            }

            Section("Boundary") {
                Text(
                    "Findings are structured conversion evidence. Generated files remain deliberately incomplete until their lowering or kernel is implemented and parity-tested."
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Unsupported Operations")
    }

    private func generateStubs(for finding: CoreAIUnsupportedOperationFinding) {
        workspace.generateStubs(for: finding)
    }
}
