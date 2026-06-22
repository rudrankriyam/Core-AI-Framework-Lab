import Foundation

struct CoreAIDeviceMemoryEvidence: Codable, Equatable, Sendable {
    let availability: CoreAIDeviceMetricAvailability
    let peakResidentBytes: UInt64?
    let source: String?

    static var unavailable: Self {
        Self(availability: .unavailable, peakResidentBytes: nil, source: nil)
    }

    func validate(path: String = "memory") throws {
        switch availability {
        case .unavailable:
            guard peakResidentBytes == nil, source == nil else {
                throw CoreAIDeviceEvidenceError.invalidValue(
                    path: path,
                    reason: "unavailable memory evidence must not contain a value or source"
                )
            }
        case .observed:
            guard let peakResidentBytes, peakResidentBytes > 0 else {
                throw CoreAIDeviceEvidenceError.invalidValue(
                    path: "\(path).peakResidentBytes",
                    reason: "observed memory evidence needs a positive byte count"
                )
            }
            try CoreAIManifestValidator.requireNonempty(
                source ?? "",
                path: "\(path).source"
            )
        }
    }
}
