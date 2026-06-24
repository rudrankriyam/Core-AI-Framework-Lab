import SwiftUI

struct CoreAIDeviceEvidenceView: View {
    @Bindable var workspace: CoreAIDeviceLabWorkspaceModel
    @Binding var isImportingEvidence: Bool

    var body: some View {
        Section {
            Button(
                "Import Runner Evidence",
                systemImage: "square.and.arrow.down",
                action: beginImport
            )
            .disabled(isImportingEvidence || workspace.isImportingEvidence)

            if workspace.isImportingEvidence {
                ProgressView("Reading and validating evidence")
            }

            if let error = workspace.importErrorMessage {
                Label(error, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            }

            if let evidence = workspace.importedEvidence {
                LabeledContent("Device", value: evidence.device.modelName)
                LabeledContent(
                    "Model identifier",
                    value: evidence.device.modelIdentifier.isEmpty
                        ? "Not reported"
                        : evidence.device.modelIdentifier
                )
                LabeledContent("iOS", value: evidence.device.operatingSystemVersion)
                LabeledContent("Artifact") {
                    Text(evidence.artifact.identifier)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent("Configuration") {
                    Text(evidence.configuration.identifier)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent(
                    "Specialization",
                    value: displayName(evidence.specialization.status.rawValue)
                )
                LabeledContent(
                    "Inference",
                    value: displayName(evidence.inference.status.rawValue)
                )
                LabeledContent(
                    "Energy",
                    value: displayName(evidence.energy.availability.rawValue)
                )
                LabeledContent(
                    "Execution placement",
                    value: displayName(evidence.placement.availability.rawValue)
                )
            } else {
                ContentUnavailableView(
                    "No Device Evidence",
                    systemImage: "iphone.slash"
                )
                .help("Run the physical harness with --evidence-json, then import that file.")
            }
        } header: {
            Label("Physical Evidence", systemImage: "doc.text.magnifyingglass")
        }
        .help("Imported JSON retains artifact and configuration SHA-256 identities.")
    }

    private func beginImport() {
        isImportingEvidence = true
    }

    private func displayName(_ rawValue: String) -> String {
        rawValue.replacing("_", with: " ").capitalized
    }
}
