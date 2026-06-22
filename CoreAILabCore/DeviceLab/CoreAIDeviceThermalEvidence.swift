import Foundation

struct CoreAIDeviceThermalEvidence: Codable, Equatable, Sendable {
    let started: CoreAIDeviceThermalState
    let ended: CoreAIDeviceThermalState

    static var unavailable: Self {
        Self(started: .unavailable, ended: .unavailable)
    }

    func validate(path: String = "thermal") throws {
        let hasUnavailableEndpoint = started == .unavailable || ended == .unavailable
        guard !hasUnavailableEndpoint || (started == .unavailable && ended == .unavailable) else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: path,
                reason: "thermal evidence must provide both endpoints or mark both unavailable"
            )
        }
    }
}
