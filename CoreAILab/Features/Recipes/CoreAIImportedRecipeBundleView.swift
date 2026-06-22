import SwiftUI

struct CoreAIImportedRecipeBundleView: View {
    let summary: CoreAIImportedRecipeBundleSummary?
    let codeApprovalState: CoreAIRecipeCodeApprovalState
    let isImporting: Bool
    let statusMessage: String
    let onApprove: () -> Void
    let onRevoke: () -> Void

    var body: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.manifest.displayName)
                    .font(.headline)
                LabeledContent("Trust", value: summary.trustState.displayName)
                LabeledContent(
                    "Bundle SHA-256",
                    value: String(summary.manifestSHA256.prefix(12))
                )
                .font(.callout.monospaced())
                LabeledContent(
                    "Code references",
                    value: "\(summary.manifest.codeReferences.count)"
                )
                ForEach(summary.manifest.codeReferences) { reference in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reference.id)
                            .font(.callout.weight(.medium))
                        Text("\(reference.language.rawValue) · \(reference.relativePath) · \(reference.entryPoint)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            CoreAIRecipeCodeApprovalView(
                state: codeApprovalState,
                onApprove: onApprove,
                onRevoke: onRevoke
            )
        } else {
            ContentUnavailableView(
                "No Imported Bundle",
                systemImage: "shippingbox",
                description: Text(statusMessage)
            )
        }

        if isImporting {
            HStack {
                ProgressView()
                Text(statusMessage)
            }
        } else if summary != nil {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

}
