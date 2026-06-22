import Foundation

enum CoreAIDeviceEvidenceError: Error, Equatable, LocalizedError {
    case invalidValue(path: String, reason: String)
    case arithmeticOverflow(path: String)

    var errorDescription: String? {
        switch self {
        case .invalidValue(let path, let reason):
            "\(path) is invalid: \(reason)"
        case .arithmeticOverflow(let path):
            "\(path) exceeds the supported integer range."
        }
    }
}
