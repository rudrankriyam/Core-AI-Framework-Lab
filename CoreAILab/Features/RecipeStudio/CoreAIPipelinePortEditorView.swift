import SwiftUI

struct CoreAIPipelinePortEditorView: View {
    @Binding var port: CoreAIPipelinePort

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Port name", text: $port.name)
                .coreAIRecipeIdentifierInput()
            Picker("Value kind", selection: $port.value.kind) {
                ForEach(CoreAIPipelineValueKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .onChange(of: port.value.kind, updateValueDefaults)

            if let scalarType = Binding($port.value.scalarType) {
                TextField("Scalar type", text: scalarType)
                    .coreAIRecipeIdentifierInput()
            }
            if let semantic = Binding($port.value.semantic) {
                TextField("Semantic", text: semantic)
                    .coreAIRecipeIdentifierInput()
            } else {
                Button("Add Semantic", systemImage: "plus", action: addSemantic)
            }
            Toggle("Optional", isOn: $port.isOptional)
        }
    }

    private func updateValueDefaults() {
        if [.tensor, .scalar].contains(port.value.kind) {
            port.value.scalarType = port.value.scalarType ?? "float32"
        } else {
            port.value.scalarType = nil
        }
        if port.value.kind == .tensor {
            port.value.shape = port.value.shape ?? [.fixed(1)]
        } else {
            port.value.shape = nil
        }
    }

    private func addSemantic() {
        port.value.semantic = ""
    }
}
