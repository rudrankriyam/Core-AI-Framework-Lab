import SwiftUI

struct CoreAIAssetReportView: View {
    let report: CoreAIModelAssetReport

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
                if report.functionNames.isEmpty {
                    Text("No functions were declared in the asset summary.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.functionNames, id: \.self) { functionName in
                        Label(functionName, systemImage: "function")
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

            Section("Source") {
                Text(report.url.path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private func valueOrFallback(_ value: String) -> String {
        value.isEmpty ? "Not declared" : value
    }
}
