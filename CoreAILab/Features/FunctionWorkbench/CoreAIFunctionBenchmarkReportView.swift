import SwiftUI

struct CoreAIFunctionBenchmarkReportView: View {
    let report: CoreAIFunctionBenchmarkReport

    var body: some View {
        DisclosureGroup {
            LabeledContent("Asset", value: report.assetName)
            LabeledContent(
                "Compute preference",
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
            durationRow("Preparation time", duration: report.specializationDuration)
            durationRow("Function load", duration: report.result.functionLoadDuration)
            durationRow("Input setup", duration: report.result.inputPreparationDuration)

            DisclosureGroup("Statistics") {
                durationRow("Minimum", duration: report.result.statistics.minimum)
                durationRow("Median", duration: report.result.statistics.median)
                durationRow("Mean", duration: report.result.statistics.mean)
                durationRow("Maximum", duration: report.result.statistics.maximum)
                durationRow(
                    "Standard deviation",
                    duration: report.result.statistics.standardDeviation
                )
                if let p95 = report.result.statistics.p95 {
                    durationRow("P95", duration: p95)
                } else {
                    LabeledContent("P95", value: "Requires at least 20 measured runs")
                }
                LabeledContent("Throughput") {
                    Text(
                        "\(report.result.statistics.runsPerSecond, format: .number.precision(.fractionLength(2))) runs/s"
                    )
                }
            }

            if !report.result.warmupDurations.isEmpty {
                DisclosureGroup("Warmup Runs") {
                    ForEach(Array(report.result.warmupDurations.enumerated()), id: \.offset) { index, duration in
                        durationRow("Warmup \(index + 1)", duration: duration)
                    }
                }
            }

            DisclosureGroup("Measured Trials") {
                ForEach(report.result.trials) { trial in
                    durationRow("Trial \(trial.index)", duration: trial.duration)
                }
            }

            DisclosureGroup("Inputs") {
                ForEach(report.inputPlans, id: \.name) { plan in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.name)
                            .font(.body.monospaced())
                        Text(inputDescription(plan))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            DisclosureGroup("Environment") {
                LabeledContent("Captured") {
                    Text(report.result.environment.capturedAt, format: .dateTime)
                }
                LabeledContent("Platform", value: report.result.environment.platform)
                LabeledContent("OS", value: report.result.environment.operatingSystem)
                LabeledContent(
                    "Architecture",
                    value: report.result.environment.deviceArchitectureName
                )
                LabeledContent(
                    "Available compute",
                    value: report.result.environment.availableComputeUnits.joined(separator: ", ")
                )
                LabeledContent(
                    "Build",
                    value: report.result.environment.buildConfiguration.rawValue
                )
                LabeledContent(
                    "Thermal state",
                    value: "\(report.result.environment.startedThermalState.title) → \(report.result.environment.endedThermalState.title)"
                )
                Text(
                    "The selected compute unit is a specialization preference, not proof of execution placement."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

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
                Text(summaryDescription)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryDescription: String {
        let milliseconds = durationMilliseconds(report.result.statistics.median)
        return "Median \(milliseconds.formatted(.number.precision(.fractionLength(2)))) ms · \(report.result.statistics.runsPerSecond.formatted(.number.precision(.fractionLength(2)))) runs/s"
    }

    @ViewBuilder
    private func durationRow(_ title: String, duration: Duration) -> some View {
        LabeledContent(title) {
            Text(
                "\(durationMilliseconds(duration), format: .number.precision(.fractionLength(2))) ms"
            )
        }
    }

    private func inputDescription(_ plan: CoreAIFunctionInputPlan) -> String {
        let shape = plan.shape.isEmpty ? "scalar" : plan.shape.map(String.init).joined(separator: " × ")
        if plan.generator == .random {
            return "\(shape) · seeded random · seed \(plan.seed)"
        }
        return "\(shape) · zeros"
    }

    private func durationMilliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return seconds * 1_000
    }
}
