import Foundation

struct CoreAIDeviceTrialOutcome: Codable, Equatable, Sendable {
    let status: CoreAIDeviceTrialStatus
    let durationMilliseconds: Double?
    let detail: String

    func validate(path: String) throws {
        try CoreAIManifestValidator.requireNonempty(detail, path: "\(path).detail")
        if let durationMilliseconds,
           !durationMilliseconds.isFinite || durationMilliseconds < 0 {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "\(path).durationMilliseconds",
                reason: "it must be finite and zero or greater"
            )
        }
        if status == .notRun, durationMilliseconds != nil {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "\(path).durationMilliseconds",
                reason: "a step that did not run cannot have a duration"
            )
        }
    }
}
