import SwiftUI

struct CoreAIRecipeCatalogEntryView: View {
    let entry: CoreAIRecipeCatalogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.displayName)
                .font(.headline)
            Text(entry.summary)
                .foregroundStyle(.secondary)
            LabeledContent("Trust", value: entry.trustState.displayName)
            LabeledContent(
                "Verification",
                value: entry.verificationState.displayName
            )
            LabeledContent(
                "Recipe SHA-256",
                value: entry.recipeManifestSHA256
            )
            .font(.callout.monospaced())
            .textSelection(.enabled)
            Text(entry.verificationNotes)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let evidenceReference = entry.evidenceReference {
                Text("Evidence: \(evidenceReference)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let evidenceSHA256 = entry.evidenceSHA256 {
                LabeledContent("Evidence SHA-256", value: evidenceSHA256)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }
}
