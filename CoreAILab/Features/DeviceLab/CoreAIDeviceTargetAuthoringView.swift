import SwiftUI

struct CoreAIDeviceTargetAuthoringView: View {
    @Bindable var workspace: CoreAIDeviceLabWorkspaceModel

    var body: some View {
        Section("iPhone Target") {
            Picker("Compute preference", selection: $workspace.preferredComputeUnit) {
                ForEach(CoreAIComputeUnitPreference.allCases, id: \.self) { preference in
                    Text(workspace.computeUnitTitle(preference))
                        .tag(preference)
                }
            }
            Toggle(
                "Expect frequent reshapes",
                isOn: $workspace.expectsFrequentReshapes
            )
            Toggle(
                "Declare a context window",
                isOn: $workspace.declaresContextWindow
            )
            if workspace.declaresContextWindow {
                Stepper(
                    "Context: \(workspace.requestedContextTokens) tokens",
                    value: $workspace.requestedContextTokens,
                    in: 1...CoreAIDeviceShapeLimits.maximumContextTokens,
                    step: 128
                )
                Stepper(
                    "Authored limit: \(workspace.maximumContextTokens) tokens",
                    value: $workspace.maximumContextTokens,
                    in: 1...CoreAIDeviceShapeLimits.maximumContextTokens,
                    step: 128
                )
            }
            Stepper(
                "Batch: \(workspace.batchSize)",
                value: $workspace.batchSize,
                in: 1...64
            )
            Stepper(
                "Token input width: \(workspace.tokenWidth)",
                value: $workspace.tokenWidth,
                in: 1...CoreAIDeviceShapeLimits.maximumDimension
            )
            Stepper(
                "Value input width: \(workspace.valueWidth)",
                value: $workspace.valueWidth,
                in: 1...CoreAIDeviceShapeLimits.maximumDimension
            )
            Toggle(
                "Leave input widths dynamic",
                isOn: $workspace.usesDynamicSequenceDimension
            )
            Text(
                "A compute preference shapes specialization options. It is not an execution-placement measurement."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
