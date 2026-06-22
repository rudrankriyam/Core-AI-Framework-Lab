import Foundation

enum CoreAINECompatibilityCategory: String, Codable, CaseIterable, Sendable {
    case precision
    case layout
    case projection
    case unsupportedOperation

    var diagnosticCategory: CoreAIDeviceDiagnosticCategory {
        switch self {
        case .precision:
            .precision
        case .layout:
            .layout
        case .projection:
            .projection
        case .unsupportedOperation:
            .unsupportedOperation
        }
    }

    var title: String {
        switch self {
        case .precision:
            "Precision"
        case .layout:
            "Tensor layout"
        case .projection:
            "Projection"
        case .unsupportedOperation:
            "Operation support"
        }
    }
}
