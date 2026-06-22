import Foundation

enum CoreAIDeviceDiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case information
    case warning
    case error

    var title: String {
        switch self {
        case .information:
            "Information"
        case .warning:
            "Warning"
        case .error:
            "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .information:
            "info.circle"
        case .warning:
            "exclamationmark.triangle"
        case .error:
            "xmark.octagon"
        }
    }
}
