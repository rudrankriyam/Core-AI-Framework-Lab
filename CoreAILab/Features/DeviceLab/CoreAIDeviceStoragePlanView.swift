import SwiftUI

struct CoreAIDeviceStoragePlanView: View {
    @Bindable var workspace: CoreAIDeviceLabWorkspaceModel

    var body: some View {
        Section("Asset Delivery") {
            Picker("Model delivery", selection: $workspace.modelDeliveryMode) {
                ForEach(CoreAIAssetDeliveryMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Stepper(
                "Model download: \(workspace.modelSizeMiB) MiB",
                value: $workspace.modelSizeMiB,
                in: 1...16_384,
                step: 16
            )
            Stepper(
                "Model installed: \(workspace.installedModelSizeMiB) MiB",
                value: $workspace.installedModelSizeMiB,
                in: 1...32_768,
                step: 16
            )
            Stepper(
                "App budget: \(workspace.appDownloadBudgetMiB) MiB",
                value: $workspace.appDownloadBudgetMiB,
                in: 1...16_384,
                step: 16
            )
            Stepper(
                "Free storage: \(workspace.availableStorageMiB) MiB",
                value: $workspace.availableStorageMiB,
                in: 1...131_072,
                step: 128
            )
            Stepper(
                "Working space: \(workspace.temporaryWorkingMiB) MiB",
                value: $workspace.temporaryWorkingMiB,
                in: 0...16_384,
                step: 16
            )

            if let error = workspace.storagePlanErrorMessage {
                Label(error, systemImage: "xmark.octagon")
                    .foregroundStyle(.secondary)
            } else if let plan = workspace.storagePlan {
                LabeledContent("App download") {
                    Text(
                        Int64(clamping: plan.appDownloadBytes),
                        format: .byteCount(style: .file)
                    )
                }
                LabeledContent("On-demand download") {
                    Text(
                        Int64(clamping: plan.onDemandDownloadBytes),
                        format: .byteCount(style: .file)
                    )
                }
                LabeledContent("Installed assets") {
                    Text(
                        Int64(clamping: plan.installedAssetBytes),
                        format: .byteCount(style: .file)
                    )
                }
                LabeledContent("Peak device requirement") {
                    Text(
                        Int64(clamping: plan.peakRequiredDeviceBytes),
                        format: .byteCount(style: .file)
                    )
                }
                if plan.diagnostics.isEmpty {
                    Label("Fits the authored budgets", systemImage: "checkmark.circle")
                } else {
                    ForEach(plan.diagnostics) { diagnostic in
                        Label(diagnostic.message, systemImage: "exclamationmark.triangle")
                    }
                }
            }
        }
    }
}
