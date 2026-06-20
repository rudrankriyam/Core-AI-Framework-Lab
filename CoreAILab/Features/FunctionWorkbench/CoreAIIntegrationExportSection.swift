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
                ProgressView("Copying and hashing the model asset…")
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
            Text("Integration Export")
        } footer: {
            Text(
                "Exports the original asset, a versioned contract manifest, generated Swift invocation code, and an optional AOT compile script using the active specialization configuration. Stateful and image-input functions remain manifest-only."
            )
        }
    }

    private var statusImage: String {
        workspace.exportedPackageURL == nil ? "info.circle" : "checkmark.circle"
    }
}
