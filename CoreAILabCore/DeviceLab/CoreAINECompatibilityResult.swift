import Foundation

enum CoreAINECompatibilityResult: String, Codable, CaseIterable, Sendable {
    case passed
    case failed
    case notEvaluated
}
