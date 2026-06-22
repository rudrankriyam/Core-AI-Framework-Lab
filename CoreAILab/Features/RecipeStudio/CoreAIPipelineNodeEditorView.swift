import SwiftUI

struct CoreAIPipelineNodeEditorView: View {
    @Binding var node: CoreAIPipelineNode

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent("Node ID") {
                Text(node.id)
                    .monospaced()
                    .textSelection(.enabled)
            }
            TextField("Title", text: $node.title)
            Picker("Kind", selection: $node.kind) {
                ForEach(CoreAIPipelineNodeKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .onChange(of: node.kind, normalizeConfiguration)

            if let reference = Binding($node.reference) {
                TextField("Executable reference", text: reference)
                    .coreAIRecipeIdentifierInput()
            }
            if let stateKey = Binding($node.stateKey) {
                TextField("State key", text: stateKey)
                    .coreAIRecipeIdentifierInput()
            }
            if let ownerNodeID = Binding($node.ownerNodeID) {
                TextField("Owner node ID", text: ownerNodeID)
                    .coreAIRecipeIdentifierInput()
            }
            if let fixedSeed = Binding($node.fixedSeed) {
                TextField("Fixed seed", value: fixedSeed, format: .number)
                    .coreAIRecipeIntegerInput()
            }
            if let maximumIterations = Binding($node.maximumIterations) {
                TextField("Maximum iterations", value: maximumIterations, format: .number)
                    .coreAIRecipeIntegerInput()
            }

            GroupBox("Inputs") {
                VStack(alignment: .leading) {
                    ForEach(node.inputs.indices, id: \.self) { index in
                        CoreAIPipelinePortEditorView(port: $node.inputs[index])
                        Button(
                            "Remove Input Port",
                            systemImage: "minus.circle",
                            action: { removeInputPort(at: index) }
                        )
                    }
                    Button("Add Input Port", systemImage: "plus", action: addInputPort)
                        .disabled(node.kind == .input)
                }
            }

            GroupBox("Outputs") {
                VStack(alignment: .leading) {
                    ForEach(node.outputs.indices, id: \.self) { index in
                        CoreAIPipelinePortEditorView(port: $node.outputs[index])
                        Button(
                            "Remove Output Port",
                            systemImage: "minus.circle",
                            action: { removeOutputPort(at: index) }
                        )
                    }
                    Button("Add Output Port", systemImage: "plus", action: addOutputPort)
                        .disabled(node.kind == .output)
                }
            }
        }
    }

    private func normalizeConfiguration() {
        node.applyConfigurationDefaults()
    }

    private func addInputPort() {
        node.inputs.append(defaultPort(prefix: "input", existing: node.inputs))
    }

    private func addOutputPort() {
        node.outputs.append(defaultPort(prefix: "output", existing: node.outputs))
    }

    private func removeInputPort(at index: Int) {
        guard node.inputs.indices.contains(index) else { return }
        node.inputs.remove(at: index)
    }

    private func removeOutputPort(at index: Int) {
        guard node.outputs.indices.contains(index) else { return }
        node.outputs.remove(at: index)
    }

    private func defaultPort(
        prefix: String,
        existing: [CoreAIPipelinePort]
    ) -> CoreAIPipelinePort {
        let names = Set(existing.map(\.name))
        var index = existing.count + 1
        while names.contains("\(prefix)_\(index)") {
            index += 1
        }
        return CoreAIPipelinePort(
            name: "\(prefix)_\(index)",
            value: CoreAIPipelineValueContract(
                kind: .tensor,
                scalarType: "float32",
                shape: [.fixed(1)]
            )
        )
    }
}
