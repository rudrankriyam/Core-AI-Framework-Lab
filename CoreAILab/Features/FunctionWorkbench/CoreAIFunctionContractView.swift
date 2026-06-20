import SwiftUI

struct CoreAIFunctionContractView: View {
    @Bindable var workspace: CoreAIFunctionWorkbenchWorkspaceModel

    var body: some View {
        Section("Function") {
            Picker("Entry point", selection: $workspace.selectedFunctionName) {
                ForEach(workspace.contracts) { contract in
                    Text(contract.name)
                        .tag(contract.name as String?)
                }
            }
            .disabled(workspace.phase.isBusy)

            if let contract = workspace.selectedContract {
                CoreAIFunctionContractValuesView(title: "Inputs", values: contract.inputs)
                CoreAIFunctionContractValuesView(title: "State", values: contract.states)
                CoreAIFunctionContractValuesView(title: "Outputs", values: contract.outputs)

                if let unsupportedReason = contract.unsupportedReason {
                    Label(unsupportedReason, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
