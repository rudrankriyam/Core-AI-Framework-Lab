struct CoreAIUnsupportedOperationFinding: Codable, Hashable, Identifiable, Sendable {
    enum Severity: String, Codable, CaseIterable, Sendable {
        case warning
        case blocker

        var title: String {
            switch self {
            case .warning:
                "Warning"
            case .blocker:
                "Blocker"
            }
        }
    }

    var id: String
    var severity: Severity
    var operatorName: String
    var modulePath: String
    var sourceFile: String
    var sourceLine: Int
    var message: String
    var exampleShapes: [String]
    var suggestedRewriteID: String
}
