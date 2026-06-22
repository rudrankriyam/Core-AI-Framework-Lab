import Foundation

struct CoreAINECompatibilityCheck: Codable, Equatable, Identifiable, Sendable {
    let category: CoreAINECompatibilityCategory
    let result: CoreAINECompatibilityResult
    let detail: String
    let source: String?

    var id: CoreAINECompatibilityCategory { category }

    func validate(path: String) throws {
        try CoreAIManifestValidator.requireNonempty(detail, path: "\(path).detail")
        switch result {
        case .passed, .failed:
            try CoreAIManifestValidator.requireNonempty(
                source ?? "",
                path: "\(path).source"
            )
        case .notEvaluated:
            guard source == nil else {
                throw CoreAIDeviceEvidenceError.invalidValue(
                    path: "\(path).source",
                    reason: "a check that was not evaluated cannot cite measured evidence"
                )
            }
        }
    }
}
