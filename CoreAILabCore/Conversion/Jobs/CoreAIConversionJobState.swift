import Foundation

enum CoreAIConversionJobState: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case cancellationRequested
    case succeeded
    case failed
    case canceled
    case interrupted

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .canceled:
            true
        case .queued, .running, .cancellationRequested, .interrupted:
            false
        }
    }

    func allowsTransition(to next: Self) -> Bool {
        switch (self, next) {
        case (.queued, .running),
             (.queued, .failed),
             (.queued, .canceled),
             (.running, .cancellationRequested),
             (.running, .succeeded),
             (.running, .failed),
             (.running, .canceled),
             (.running, .interrupted),
             (.cancellationRequested, .succeeded),
             (.cancellationRequested, .failed),
             (.cancellationRequested, .canceled),
             (.cancellationRequested, .interrupted),
             (.interrupted, .queued):
            true
        default:
            false
        }
    }
}
