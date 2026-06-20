import SwiftUI

struct CoreAIIntegrationExportSection: View {
    let workspace: CoreAIFunctionWorkbenchWorkspaceModel
    let chooseDestination: () -> Void

    var body: some View {
        @Bindable var workspace = workspace
        Section {
            Toggle(
                "AOT expects frequent reshapes",
                isOn: $workspace.exportExpectFrequentReshapes
            )
            .disabled(workspace.isExportingIntegration)

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
                "Exports the original asset, a versioned contract manifest, generated Swift invocation code, and an optional AOT compile script. Stateful and image-input functions remain manifest-only."
            )
        }
    }

    private var statusImage: String {
        workspace.exportedPackageURL == nil ? "info.circle" : "checkmark.circle"
    }
}
