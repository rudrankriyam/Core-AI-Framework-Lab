import SwiftUI

struct CoreAIDeviceEvidenceView: View {
    @Bindable var workspace: CoreAIDeviceLabWorkspaceModel
    @Binding var isImportingEvidence: Bool

    var body: some View {
        Section("Physical Evidence") {
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
                    .foregroundStyle(.secondary)
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
                LabeledContent("Artifact", value: evidence.artifact.identifier)
                LabeledContent("Configuration", value: evidence.configuration.identifier)
                LabeledContent(
                    "Specialization",
                    value: evidence.specialization.status.rawValue
                )
                LabeledContent("Inference", value: evidence.inference.status.rawValue)
                LabeledContent("Energy", value: evidence.energy.availability.rawValue)
                LabeledContent(
                    "Execution placement",
                    value: evidence.placement.availability.rawValue
                )
                Text(
                    "Artifact and configuration SHA-256 identities are retained in the imported JSON."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    "No Device Evidence",
                    systemImage: "iphone.slash",
                    description: Text(
                        "Run the physical harness or its dry run with --evidence-json, then import that file."
                    )
                )
            }
        }
    }

    private func beginImport() {
        isImportingEvidence = true
    }
}
