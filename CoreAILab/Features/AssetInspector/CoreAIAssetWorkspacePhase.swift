import Foundation

enum CoreAIAssetWorkspacePhase: Sendable, Equatable {
    case idle
    case inspecting
    case ready
    case checkingCache
    case specializing
    case removingCache

    var isBusy: Bool {
        switch self {
        case .inspecting, .checkingCache, .specializing, .removingCache:
            true
        case .idle, .ready:
            false
        }
    }
}
