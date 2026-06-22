import SwiftUI

struct CoreAIProjectDescriptorSnapshotView: View {
    let snapshot: CoreAIAssetDescriptorSnapshot
    let inspectedAt: Date?

    var body: some View {
        Section("Model Descriptor") {
            LabeledContent("Valid Core AI asset", value: snapshot.isValid ? "Yes" : "No")
            LabeledContent("Functions", value: snapshot.functions.count.formatted())
            LabeledContent(
                "Compute types",
                value: snapshot.computeTypes.isEmpty
                    ? "Not reported"
                    : snapshot.computeTypes.joined(separator: ", ")
            )
            if let inspectedAt {
                LabeledContent("Inspected") {
                    Text(
                        inspectedAt,
                        format: .dateTime.day().month().year().hour().minute()
                    )
                }
            }
            if !snapshot.author.isEmpty {
                LabeledContent("Author", value: snapshot.author)
            }
            if !snapshot.license.isEmpty {
                LabeledContent("License", value: snapshot.license)
            }
            if !snapshot.assetDescription.isEmpty {
                Text(snapshot.assetDescription)
                    .foregroundStyle(.secondary)
            }
            if !snapshot.storageTypes.isEmpty {
                DisclosureGroup("Storage types") {
                    ForEach(snapshot.storageTypes) { storageType in
                        LabeledContent(
                            storageType.typeName,
                            value: storageType.count,
                            format: .number
                        )
                    }
                }
            }
            if !snapshot.operationDistribution.isEmpty {
                DisclosureGroup("Operation distribution") {
                    ForEach(snapshot.operationDistribution) { operation in
                        LabeledContent(
                            operation.operationName,
                            value: operation.count,
                            format: .number
                        )
                    }
                }
            }
            ForEach(snapshot.functions) { function in
                DisclosureGroup {
                    CoreAIAssetSignatureValuesView(
                        title: "Inputs",
                        values: function.inputs
                    )
                    CoreAIAssetSignatureValuesView(
                        title: "State",
                        values: function.states
                    )
                    CoreAIAssetSignatureValuesView(
                        title: "Outputs",
                        values: function.outputs
                    )
                } label: {
                    Label(function.name, systemImage: "function")
                        .font(.body.monospaced())
                }
            }
        }
    }
}
