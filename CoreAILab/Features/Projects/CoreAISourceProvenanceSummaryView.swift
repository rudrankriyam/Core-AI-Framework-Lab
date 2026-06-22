import SwiftUI

struct CoreAISourceProvenanceSummaryView: View {
    let provenance: CoreAISourceProvenanceRecord?
    let edit: () -> Void

    var body: some View {
        Section("Source Provenance") {
            if let provenance {
                LabeledContent(
                    "Type",
                    value: provenance.kind?.title ?? "Unsupported"
                )
                if !provenance.sourceLocation.isEmpty {
                    LabeledContent("Location") {
                        Text(provenance.sourceLocation)
                            .textSelection(.enabled)
                    }
                }
                if !provenance.providerName.isEmpty {
                    LabeledContent("Provider", value: provenance.providerName)
                }
                if !provenance.licenseName.isEmpty {
                    LabeledContent("License", value: provenance.licenseName)
                }
                if !provenance.notes.isEmpty {
                    Text(provenance.notes)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No source provenance has been recorded.")
                    .foregroundStyle(.secondary)
            }
            Button(
                "Edit Source Provenance",
                systemImage: "pencil",
                action: edit
            )
        }
    }
}
