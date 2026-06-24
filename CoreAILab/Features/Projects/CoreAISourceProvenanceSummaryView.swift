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
                    LabeledContent("Notes", value: provenance.notes)
                }
            } else {
                Label("No Source Provenance", systemImage: "minus.circle")
            }
            Button(
                "Edit Source Provenance",
                systemImage: "pencil",
                action: edit
            )
        }
    }
}
