import SwiftUI

struct CoreAIFunctionBenchmarkStatisticsView: View {
    let statistics: CoreAIBenchmarkStatistics

    var body: some View {
        DisclosureGroup("Statistics") {
            CoreAIBenchmarkDurationRow(title: "Minimum", duration: statistics.minimum)
            CoreAIBenchmarkDurationRow(title: "Median", duration: statistics.median)
            CoreAIBenchmarkDurationRow(title: "Mean", duration: statistics.mean)
            CoreAIBenchmarkDurationRow(title: "Maximum", duration: statistics.maximum)
            CoreAIBenchmarkDurationRow(
                title: "Standard deviation",
                duration: statistics.standardDeviation
            )
            if let p95 = statistics.p95 {
                CoreAIBenchmarkDurationRow(title: "P95", duration: p95)
            } else {
                LabeledContent("P95", value: "Requires at least 20 measured runs")
            }
            LabeledContent("Sequential throughput") {
                Text(
                    "\(statistics.runsPerSecond, format: .number.precision(.fractionLength(2))) runs/s"
                )
            }
        }
    }
}
