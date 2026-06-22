import SwiftUI

struct CoreAIAssetReportView: View {
    let report: CoreAIModelAssetReport
    @Bindable var workspace: CoreAIAssetWorkspaceModel
    let allowsCacheRemoval: Bool

    var body: some View {
        List {
            Section("Asset") {
                LabeledContent("Name", value: report.url.lastPathComponent)
                LabeledContent("Valid Core AI asset", value: report.isValid ? "Yes" : "No")
                LabeledContent("Author", value: valueOrFallback(report.author))
                LabeledContent("License", value: valueOrFallback(report.license))
                if !report.description.isEmpty {
                    Text(report.description)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Functions") {
                if report.functions.isEmpty {
                    Text("No functions were declared in the asset summary.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.functions) { function in
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

            Section("Compute Types") {
                if report.computeTypes.isEmpty {
                    Text("No compute types were reported.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.computeTypes, id: \.self) { computeType in
                        Text(computeType)
                    }
                }
            }

            Section("Storage Types") {
                if report.storageTypes.isEmpty {
                    Text("No storage statistics were reported.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.storageTypes) { storageType in
                        LabeledContent(
                            storageType.typeName,
                            value: storageType.count,
                            format: .number
                        )
                    }
                }
            }

            Section("Operation Distribution") {
                if report.operationDistribution.isEmpty {
                    Text("No operation statistics were reported.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.operationDistribution) { operation in
                        LabeledContent(
                            operation.operationName,
                            value: operation.count,
                            format: .number
                        )
                    }
                }
            }

            Section("Source") {
                Text(report.url.path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }

            CoreAISpecializationControlsView(
                workspace: workspace,
                allowsCacheRemoval: allowsCacheRemoval
            )
        }
    }

    private func valueOrFallback(_ value: String) -> String {
        value.isEmpty ? "Not declared" : value
    }
}
