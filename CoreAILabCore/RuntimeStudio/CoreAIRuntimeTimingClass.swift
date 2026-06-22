import Foundation

enum CoreAIRuntimeTimingClass: String, Codable, Equatable, Sendable {
    case cold
    case warm

    var title: String {
        switch self {
        case .cold:
            "Cold"
        case .warm:
            "Warm"
        }
    }
}
