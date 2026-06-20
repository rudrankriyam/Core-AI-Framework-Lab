import Foundation

enum CoreAIBuildConfiguration: String, Sendable, Equatable {
    case debug = "Debug"
    case release = "Release"

    static var current: Self {
        #if DEBUG
        .debug
        #else
        .release
        #endif
    }
}

enum CoreAIThermalState: String, Sendable, Equatable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    static var current: Self {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            .nominal
        case .fair:
            .fair
        case .serious:
            .serious
        case .critical:
            .critical
        @unknown default:
            .unknown
        }
    }

    var title: String {
        rawValue.capitalized
    }
}

struct CoreAIBenchmarkEnvironment: Sendable, Equatable {
    let capturedAt: Date
    let platform: String
    let operatingSystem: String
    let deviceArchitectureName: String
    let availableComputeUnits: [String]
    let buildConfiguration: CoreAIBuildConfiguration
    let startedThermalState: CoreAIThermalState
    let endedThermalState: CoreAIThermalState

    static func current(
        startedThermalState: CoreAIThermalState,
        endedThermalState: CoreAIThermalState
    ) -> Self {
        let discovery = CoreAIDiscoverySnapshot.current()
        return Self(
            capturedAt: .now,
            platform: currentPlatform,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceArchitectureName: discovery.deviceArchitectureName,
            availableComputeUnits: discovery.availableComputeUnits,
            buildConfiguration: .current,
            startedThermalState: startedThermalState,
            endedThermalState: endedThermalState
        )
    }

    private static var currentPlatform: String {
        #if os(macOS)
        "macOS"
        #elseif os(iOS)
        "iOS"
        #elseif os(tvOS)
        "tvOS"
        #elseif os(watchOS)
        "watchOS"
        #elseif os(visionOS)
        "visionOS"
        #else
        "Unknown"
        #endif
    }
}
