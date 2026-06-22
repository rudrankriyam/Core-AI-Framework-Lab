import Foundation

struct CoreAIDevicePlacementEvidence: Codable, Equatable, Sendable {
    let availability: CoreAIDeviceMetricAvailability
    let actualComputeUnits: [String]
    let source: String?

    static var unavailable: Self {
        Self(availability: .unavailable, actualComputeUnits: [], source: nil)
    }

    var reportsNeuralEnginePlacement: Bool {
        availability == .observed
            && actualComputeUnits.contains {
                let normalized = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return normalized == "neural engine" || normalized == "ane"
            }
    }

    func validate(path: String = "placement") throws {
        switch availability {
        case .unavailable:
            guard actualComputeUnits.isEmpty, source == nil else {
                throw CoreAIDeviceEvidenceError.invalidValue(
                    path: path,
                    reason: "unavailable placement evidence must not name compute units or a source"
                )
            }
        case .observed:
            guard !actualComputeUnits.isEmpty else {
                throw CoreAIDeviceEvidenceError.invalidValue(
                    path: "\(path).actualComputeUnits",
                    reason: "observed placement needs at least one measured compute unit"
                )
            }
            try CoreAIManifestValidator.requireNonempty(
                source ?? "",
                path: "\(path).source"
            )
            try CoreAIManifestValidator.requireUniqueIdentifiers(
                actualComputeUnits,
                path: "\(path).actualComputeUnits",
                identifier: { $0.lowercased() }
            )
            for (index, computeUnit) in actualComputeUnits.enumerated() {
                try CoreAIManifestValidator.requireNonempty(
                    computeUnit,
                    path: "\(path).actualComputeUnits[\(index)]"
                )
            }
        }
    }
}
