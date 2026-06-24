import SwiftUI

struct CoreAIPipelineStudioView: View {
    @Bindable var workspace: CoreAIRecipeStudioWorkspaceModel

    var body: some View {
        let displayedEdges = workspace.displayedPipelineEdges

        Form {
            Section("Pipeline Manifest") {
                TextField("Display name", text: $workspace.recipe.pipeline.displayName)
                TextField("Pipeline ID", text: $workspace.recipe.pipeline.id)
                    .coreAIRecipeIdentifierInput()
                TextField(
                    "Host-operator registry version",
                    value: $workspace.recipe.pipeline.hostOperatorRegistryVersion,
                    format: .number
                )
                .coreAIRecipeIntegerInput()
            }

            Section("Asset-Level Nodes") {
                ForEach($workspace.recipe.pipeline.nodes) { $node in
                    DisclosureGroup(node.title.isEmpty ? node.id : node.title) {
                        CoreAIPipelineNodeEditorView(
                            workspace: workspace,
                            node: $node
                        )
                        Button(
                            "Remove Node",
                            systemImage: "trash",
                            role: .destructive,
                            action: { removeNode(id: node.id) }
                        )
                    }
                }

                Menu("Add Node", systemImage: "plus") {
                    ForEach(CoreAIPipelineNodeKind.allCases, id: \.self) { kind in
                        Button(kind.title, action: { addNode(kind: kind) })
                    }
                }
            }

            Section {
                Picker("Source", selection: $workspace.selectedSourceEndpoint) {
                    Text("Choose source").tag(nil as CoreAIPipelineEndpoint?)
                    ForEach(workspace.sourceEndpoints) { endpoint in
                        Text(endpoint.diagnosticDescription)
                            .tag(endpoint as CoreAIPipelineEndpoint?)
                    }
                }
                Picker("Destination", selection: $workspace.selectedDestinationEndpoint) {
                    Text("Choose destination").tag(nil as CoreAIPipelineEndpoint?)
                    ForEach(workspace.destinationEndpoints) { endpoint in
                        Text(endpoint.diagnosticDescription)
                            .tag(endpoint as CoreAIPipelineEndpoint?)
                    }
                }
                Button(
                    "Connect Ports",
                    systemImage: "link",
                    action: workspace.connectSelectedEndpoints
                )
                .disabled(!workspace.canConnectSelectedEndpoints)
                .help("Each destination accepts one compatible source value contract.")
            } header: {
                Text("Connect Typed Ports")
            }

            Section("Edges") {
                if displayedEdges.isEmpty {
                    ContentUnavailableView("No Edges", systemImage: "arrow.triangle.branch")
                }
                ForEach(displayedEdges) { edge in
                    LabeledContent(
                        edge.source.diagnosticDescription,
                        value: edge.destination.diagnosticDescription
                    )
                        .textSelection(.enabled)
                    Button(
                        "Remove \(edge.diagnosticDescription)",
                        systemImage: "minus.circle",
                        action: { removeEdge(id: edge.id) }
                    )
                }
            }

            Section("Validation") {
                CoreAIPipelineValidationIssuesView(issues: workspace.pipelineIssues)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Pipeline Studio")
    }

    private func addNode(kind: CoreAIPipelineNodeKind) {
        workspace.addPipelineNode(kind: kind)
    }

    private func removeNode(id: String) {
        workspace.removePipelineNode(id: id)
    }

    private func removeEdge(id: CoreAIPipelineEdge.ID) {
        workspace.removePipelineEdge(id: id)
    }
}
