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
            Text(entry.verificationNotes)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
