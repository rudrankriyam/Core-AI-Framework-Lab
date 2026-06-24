import SwiftUI

struct CoreAIAssetReportView: View {
    let report: CoreAIModelAssetReport
    @Bindable var workspace: CoreAIAssetWorkspaceModel
    let allowsCacheRemoval: Bool

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: report.url.lastPathComponent)
                LabeledContent("Core AI asset") {
                    Label(
                        report.isValid ? "Valid" : "Invalid",
                        systemImage: report.isValid
                            ? "checkmark.circle.fill"
                            : "xmark.circle.fill"
                    )
                }
                LabeledContent("Author", value: valueOrFallback(report.author))
                LabeledContent("License", value: valueOrFallback(report.license))
                if !report.description.isEmpty {
                    LabeledContent("Description", value: report.description)
                }
            } header: {
                Label("Asset", systemImage: "shippingbox")
            }

            Section {
                if report.functions.isEmpty {
                    Label("No Functions Declared", systemImage: "minus.circle")
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
            } header: {
                Label("Functions", systemImage: "function")
            }

            Section {
                if report.computeTypes.isEmpty {
                    Label("Not Reported", systemImage: "minus.circle")
                } else {
                    ForEach(report.computeTypes, id: \.self) { computeType in
                        Text(computeType)
                    }
                }
            } header: {
                Label("Compute Types", systemImage: "cpu")
            }

            Section {
                if report.storageTypes.isEmpty {
                    Label("Not Reported", systemImage: "minus.circle")
                } else {
                    ForEach(report.storageTypes) { storageType in
                        LabeledContent(
                            storageType.typeName,
                            value: storageType.count,
                            format: .number
                        )
                    }
                }
            } header: {
                Label("Storage Types", systemImage: "internaldrive")
            }

            Section {
                if report.operationDistribution.isEmpty {
                    Label("Not Reported", systemImage: "minus.circle")
                } else {
                    ForEach(report.operationDistribution) { operation in
                        LabeledContent(
                            operation.operationName,
                            value: operation.count,
                            format: .number
                        )
                    }
                }
            } header: {
                Label("Operation Distribution", systemImage: "chart.bar.xaxis")
            }

            Section {
                Text(report.url.path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            } header: {
                Label("Source", systemImage: "folder")
            }

            CoreAISpecializationControlsView(
                workspace: workspace,
                allowsCacheRemoval: allowsCacheRemoval
            )
        }
        .formStyle(.grouped)
    }

    private func valueOrFallback(_ value: String) -> String {
        value.isEmpty ? "Not declared" : value
    }
}
