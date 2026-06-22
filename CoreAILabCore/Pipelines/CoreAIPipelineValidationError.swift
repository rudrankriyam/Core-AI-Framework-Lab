import Foundation

struct CoreAIPipelineValidationError: LocalizedError, Sendable {
    let issues: [CoreAIPipelineValidationIssue]

    var errorDescription: String? {
        issues.map(\.message).joined(separator: "\n")
    }
}
