import SwiftUI

struct CoreAIIntegrationExportSection: View {
    let workspace: CoreAIFunctionWorkbenchWorkspaceModel
    let chooseDestination: () -> Void

    var body: some View {
        Section {
            LabeledContent(
                "Specialization",
                value: workspace.assetWorkspace.selectedProfile.title
            )
            LabeledContent(
                "Frequent reshapes",
                value: workspace.assetWorkspace.expectFrequentReshapes ? "Expected" : "Not expected"
            )

            if workspace.isExportingIntegration {
                ProgressView("Packaging and hashing the model asset…")
                Button(
                    "Cancel Export",
                    systemImage: "xmark",
                    role: .cancel,
                    action: workspace.cancelIntegrationExport
                )
            } else {
                Button(
                    "Export Integration",
                    systemImage: "shippingbox.and.arrow.backward",
                    action: chooseDestination
                )
                .disabled(!workspace.canExportIntegration)
            }

            if let status = workspace.exportStatusMessage {
                Label(status, systemImage: statusImage)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("Integration Export", systemImage: "shippingbox.and.arrow.backward")
        } footer: {
            Text(
                "Creates a standalone Swift package with the original asset, checksums, notices, typed metadata, generated invocation code, and an offline verifier. The optional AOT script never runs automatically. Stateful and image-input functions remain manifest-only."
            )
        }
    }

    private var statusImage: String {
        workspace.exportedPackageURL == nil ? "info.circle" : "checkmark.circle"
    }
}
