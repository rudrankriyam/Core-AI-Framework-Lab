import CoreAI
import Foundation

struct CoreAIDiscoverySnapshot: Sendable {
    let frameworkName: String
    let deviceArchitectureName: String
    let availableComputeUnits: [String]
    let defaultSpecializationDescription: String
    let cpuOnlySpecializationDescription: String

    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func current() -> CoreAIDiscoverySnapshot {
        CoreAIDiscoverySnapshot(
            frameworkName: "CoreAI.framework",
            deviceArchitectureName: AIModel.deviceArchitectureName,
            availableComputeUnits: ComputeUnitKind.availableKinds
                .map(Self.describeComputeUnit)
                .sorted(),
            defaultSpecializationDescription: Self.describe(SpecializationOptions.default),
            cpuOnlySpecializationDescription: Self.describe(SpecializationOptions.cpuOnly)
        )
    }

    private static func describeComputeUnit(_ unit: ComputeUnitKind) -> String {
        switch unit {
        case .cpu:
            "CPU"
        case .gpu:
            "GPU"
        case .neuralEngine:
            "Neural Engine"
        @unknown default:
            "Unknown"
        }
    }

    private static func describe(_ options: SpecializationOptions) -> String {
        let allowed = options.allowedComputeUnitKinds
            .map(Self.describeComputeUnit)
            .sorted()
            .joined(separator: ", ")
        let preferred = options.preferredComputeUnitKind.map(Self.describeComputeUnit) ?? "system"
        return "preferred: \(preferred), allowed: \(allowed), frequent reshapes: \(options.expectFrequentReshapes)"
    }
}

