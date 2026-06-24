import SwiftUI

struct CoreAIFunctionBenchmarkActionsView: View {
    let workspace: CoreAIFunctionWorkbenchWorkspaceModel
    let axis: Axis

    var body: some View {
        @Bindable var workspace = workspace
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout())
            : AnyLayout(VStackLayout(alignment: .leading))

        layout {
            Button(
                "Run Benchmark",
                systemImage: "gauge.with.dots.needle.67percent",
                action: workspace.startBenchmark
            )
            .buttonStyle(.borderedProminent)
            .disabled(!workspace.canBenchmark)

            if workspace.phase == .benchmarking {
                Button(
                    "Stop After Current Inference",
                    systemImage: "stop.fill",
                    role: .cancel,
                    action: workspace.stopBenchmarkAfterCurrentInference
                )
            }

            Button(
                "Clear History",
                systemImage: "trash",
                action: workspace.clearBenchmarkHistory
            )
            .disabled(workspace.phase.isBusy || workspace.benchmarkHistory.isEmpty)
        }
    }
}
