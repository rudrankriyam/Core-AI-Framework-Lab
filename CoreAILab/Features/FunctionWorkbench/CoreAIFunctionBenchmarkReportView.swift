import SwiftUI

struct CoreAIFunctionBenchmarkReportView: View {
    let report: CoreAIFunctionBenchmarkReport
    let exportEvidence: (CoreAIFunctionBenchmarkReport) -> Void

    var body: some View {
        DisclosureGroup {
            LabeledContent("Asset", value: report.assetName)
            LabeledContent(
                "Compute profile",
                value: report.specializationConfiguration.profile.title
            )
            LabeledContent(
                "Frequent reshapes",
                value: report.specializationConfiguration.expectFrequentReshapes ? "Expected" : "Not expected"
            )
            LabeledContent(
                "Model preparation",
                value: report.loadedFromCache ? "Loaded from cache" : "Specialized on device"
            )
            CoreAIBenchmarkDurationRow(
                title: "Preparation time",
                duration: report.specializationDuration
            )
            CoreAIBenchmarkDurationRow(
                title: "Function load",
                duration: report.result.functionLoadDuration
            )
            CoreAIBenchmarkDurationRow(
                title: "Input setup",
                duration: report.result.inputPreparationDuration
            )
            CoreAIFunctionBenchmarkStatisticsView(
                statistics: report.result.statistics
            )
            CoreAIFunctionBenchmarkRunsView(result: report.result)
            CoreAIFunctionBenchmarkInputsView(inputPlans: report.inputPlans)
            CoreAIFunctionBenchmarkEnvironmentView(
                environment: report.result.environment
            )
            Button(
                "Export Evidence JSON",
                systemImage: "square.and.arrow.up",
                action: export
            )

            if !report.result.outputs.isEmpty {
                DisclosureGroup("Final Output Check") {
                    ForEach(report.result.outputs) { output in
                        CoreAIFunctionOutputSummaryView(output: output)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(report.result.functionName)
                    .font(.headline.monospaced())
                if report.result.stoppedEarly {
                    Text("Stopped early · completed trials retained")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(summaryDescription)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryDescription: String {
        let milliseconds = report.result.statistics.median.coreAIMilliseconds
        return "Median \(milliseconds.formatted(.number.precision(.fractionLength(2)))) ms · \(report.result.statistics.runsPerSecond.formatted(.number.precision(.fractionLength(2)))) runs/s"
    }

    private func export() {
        exportEvidence(report)
    }
}
