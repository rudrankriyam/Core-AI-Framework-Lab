import SwiftUI

struct CoreAIFunctionBenchmarkControlsView: View {
    @Bindable var workspace: CoreAIFunctionWorkbenchWorkspaceModel

    var body: some View {
        Section {
            Stepper(
                "Warmup runs: \(workspace.benchmarkConfiguration.warmupRuns)",
                value: $workspace.benchmarkConfiguration.warmupRuns,
                in: CoreAIFunctionBenchmarkConfiguration.warmupRange
            )
            .disabled(workspace.phase.isBusy)

            Stepper(
                "Measured runs: \(workspace.benchmarkConfiguration.measuredRuns)",
                value: $workspace.benchmarkConfiguration.measuredRuns,
                in: CoreAIFunctionBenchmarkConfiguration.measuredRunRange
            )
            .disabled(workspace.phase.isBusy)

            HStack {
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

            if let message = workspace.benchmarkStatusMessage {
                Label(message, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }

            if CoreAIBuildConfiguration.current == .debug {
                Label(
                    "Debug build results are provisional. Use a Release build for comparisons.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Benchmark")
        } footer: {
            Text(
                "Warmups are excluded. Measured runs reuse one function and one deterministic input set, execute sequentially, and remain visible individually. Stopping takes effect between Core AI inference calls."
            )
        }
    }
}
