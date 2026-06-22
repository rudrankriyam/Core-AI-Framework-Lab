import SwiftUI

struct CoreAIFunctionBenchmarkEnvironmentView: View {
    let environment: CoreAIBenchmarkEnvironment

    var body: some View {
        DisclosureGroup("Environment") {
            LabeledContent("Captured") {
                Text(environment.capturedAt, format: .dateTime)
            }
            LabeledContent("Platform", value: environment.platform)
            LabeledContent("OS", value: environment.operatingSystem)
            LabeledContent("Architecture", value: environment.deviceArchitectureName)
            LabeledContent(
                "Available compute",
                value: environment.availableComputeUnits.joined(separator: ", ")
            )
            LabeledContent(
                "Logical processors",
                value: environment.processorCount.formatted()
            )
            LabeledContent("Physical memory") {
                Text(
                    Int64(clamping: environment.physicalMemoryBytes),
                    format: .byteCount(style: .memory)
                )
            }
            LabeledContent("Build", value: environment.buildConfiguration.rawValue)
            LabeledContent(
                "Thermal state",
                value: "\(environment.startedThermalState.title) → \(environment.endedThermalState.title)"
            )
            CoreAIBenchmarkToolchainView(toolchain: environment.toolchain)
            Text(
                "CPU-only restricts allowed compute to the CPU. GPU and Neural Engine profiles are preferences and do not prove execution placement."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
