import Foundation

enum CoreAIConversionPhase: Equatable, Sendable {
    case idle
    case checking
    case ready
    case running
    case canceling
    case succeeded
    case failed
    case canceled

    var title: String {
        switch self {
        case .idle:
            "Set up a conversion"
        case .checking:
            "Checking environment"
        case .ready:
            "Ready to convert"
        case .running:
            "Conversion running"
        case .canceling:
            "Canceling conversion"
        case .succeeded:
            "Conversion complete"
        case .failed:
            "Conversion failed"
        case .canceled:
            "Conversion canceled"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "arrow.triangle.2.circlepath"
        case .checking:
            "checkmark.circle"
        case .ready:
            "checkmark.circle.fill"
        case .running:
            "gearshape.2"
        case .canceling:
            "stop.circle"
        case .succeeded:
            "checkmark.seal.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .canceled:
            "xmark.circle"
        }
    }

    var isActive: Bool {
        self == .running || self == .canceling
    }

    var isBusy: Bool {
        self == .checking || isActive
    }

    var allowsStartingConversion: Bool {
        !isBusy
    }

    static func afterEnvironmentCheck(
        canConvert: Bool,
        conversionIsStarting: Bool
    ) -> Self {
        if conversionIsStarting {
            return .checking
        }
        return canConvert ? .ready : .idle
    }
}
