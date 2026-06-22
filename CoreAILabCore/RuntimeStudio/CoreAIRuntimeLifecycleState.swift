import Foundation

enum CoreAIRuntimeLifecycleState: String, Codable, Equatable, Sendable {
    case canceled
    case failed
    case started
    case succeeded

    var title: String {
        switch self {
        case .canceled:
            "Canceled"
        case .failed:
            "Failed"
        case .started:
            "Running"
        case .succeeded:
            "Succeeded"
        }
    }

    var systemImage: String {
        switch self {
        case .canceled:
            "stop.circle"
        case .failed:
            "exclamationmark.triangle"
        case .started:
            "hourglass"
        case .succeeded:
            "checkmark.circle"
        }
    }
}
