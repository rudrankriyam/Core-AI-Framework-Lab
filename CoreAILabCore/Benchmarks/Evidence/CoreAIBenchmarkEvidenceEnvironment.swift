import Foundation

struct CoreAIBenchmarkEvidenceEnvironment: Codable, Sendable, Equatable {
    let capturedAtUnixMilliseconds: Int64
    let platform: String
    let operatingSystem: String
    let coreAIDeviceArchitecture: String
    let availableComputeUnits: [String]
    let processorCount: Int
    let physicalMemoryBytes: UInt64
    let buildConfiguration: String
    let startedThermalState: String
    let endedThermalState: String
    let toolchain: CoreAIBenchmarkToolchain

    init(environment: CoreAIBenchmarkEnvironment) {
        capturedAtUnixMilliseconds = Int64(
            (environment.capturedAt.timeIntervalSince1970 * 1_000).rounded(.down)
        )
        platform = environment.platform
        operatingSystem = environment.operatingSystem
        coreAIDeviceArchitecture = environment.deviceArchitectureName
        availableComputeUnits = environment.availableComputeUnits.sorted()
        processorCount = environment.processorCount
        physicalMemoryBytes = environment.physicalMemoryBytes
        buildConfiguration = environment.buildConfiguration.rawValue
        startedThermalState = environment.startedThermalState.rawValue
        endedThermalState = environment.endedThermalState.rawValue
        toolchain = environment.toolchain
    }
}
