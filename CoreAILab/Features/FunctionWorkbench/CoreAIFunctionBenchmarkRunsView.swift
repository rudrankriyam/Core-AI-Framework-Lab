import SwiftUI

struct CoreAIFunctionBenchmarkRunsView: View {
    let result: CoreAIFunctionBenchmarkResult

    var body: some View {
        if !result.warmupDurations.isEmpty {
            DisclosureGroup("Warmup Runs") {
                ForEach(result.warmupDurations.indices, id: \.self) { index in
                    CoreAIBenchmarkDurationRow(
                        title: "Warmup \(index + 1)",
                        duration: result.warmupDurations[index]
                    )
                }
            }
        }

        DisclosureGroup("Measured Trials") {
            ForEach(result.trials) { trial in
                CoreAIBenchmarkDurationRow(
                    title: "Trial \(trial.index)",
                    duration: trial.duration
                )
            }
        }
    }
}
