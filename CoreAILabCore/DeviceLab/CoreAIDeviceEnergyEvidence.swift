import Foundation

struct CoreAIDeviceEnergyEvidence: Codable, Equatable, Sendable {
    let availability: CoreAIDeviceMetricAvailability
    let joules: Double?
    let source: String?

    static var unavailable: Self {
        Self(availability: .unavailable, joules: nil, source: nil)
    }

    func validate(path: String = "energy") throws {
        switch availability {
        case .unavailable:
            guard joules == nil, source == nil else {
                throw CoreAIDeviceEvidenceError.invalidValue(
                    path: path,
                    reason: "unavailable energy evidence must not contain a value or source"
                )
            }
        case .observed:
            guard let joules, joules.isFinite, joules >= 0 else {
                throw CoreAIDeviceEvidenceError.invalidValue(
                    path: "\(path).joules",
                    reason: "observed energy must be finite and zero or greater"
                )
            }
            try CoreAIManifestValidator.requireNonempty(
                source ?? "",
                path: "\(path).source"
            )
        }
    }
}
