import SwiftUI

struct CoreAIRecipeCatalogEntryView: View {
    let entry: CoreAIRecipeCatalogEntry

    var body: some View {
        VStack(alignment: .leading) {
            Label(entry.displayName, systemImage: "waveform.badge.microphone")
                .font(.headline)
            Text(entry.summary)
                .foregroundStyle(.secondary)

            Divider()

            LabeledContent("Trust") {
                Label(entry.trustState.displayName, systemImage: trustSystemImage)
            }
            LabeledContent("Verification") {
                Label(
                    entry.verificationState.displayName,
                    systemImage: verificationSystemImage
                )
            }
            LabeledContent("Recipe SHA-256") {
                Text(entry.recipeManifestSHA256)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Text(entry.verificationNotes)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let evidenceReference = entry.evidenceReference {
                LabeledContent("Evidence") {
                    Text(evidenceReference)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            if let evidenceSHA256 = entry.evidenceSHA256 {
                LabeledContent("Evidence SHA-256") {
                    Text(evidenceSHA256)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var trustSystemImage: String {
        switch entry.trustState {
        case .bundledCurated:
            "checkmark.seal.fill"
        case .publisherReviewed:
            "person.badge.shield.checkmark"
        case .importedUntrusted:
            "exclamationmark.shield"
        }
    }

    private var verificationSystemImage: String {
        switch entry.verificationState {
        case .notVerified:
            "questionmark.diamond"
        case .schemaValidated:
            "doc.badge.checkmark"
        case .fixturesValidated:
            "checkmark.rectangle.stack"
        case .hardwareValidated:
            "checkmark.circle.fill"
        }
    }
}
