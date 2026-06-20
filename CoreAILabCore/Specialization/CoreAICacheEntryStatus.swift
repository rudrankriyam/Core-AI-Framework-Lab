import Foundation

enum CoreAICacheEntryStatus: Sendable, Equatable {
    case unchecked
    case checking
    case cached
    case notCached

    var title: String {
        switch self {
        case .unchecked:
            "Not checked"
        case .checking:
            "Checking"
        case .cached:
            "Cached"
        case .notCached:
            "Not cached"
        }
    }

    var systemImage: String {
        switch self {
        case .unchecked:
            "questionmark.circle"
        case .checking:
            "arrow.triangle.2.circlepath"
        case .cached:
            "checkmark.circle.fill"
        case .notCached:
            "circle.dashed"
        }
    }
}
