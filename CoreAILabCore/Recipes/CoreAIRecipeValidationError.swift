import Foundation

struct CoreAIRecipeValidationError: LocalizedError, Sendable {
    var issues: [CoreAIRecipeValidationIssue]

    var errorDescription: String? {
        issues.map(\.message).joined(separator: "\n")
    }
}
