import Foundation

enum CoreAIFunctionWorkbenchPhase: Sendable, Equatable {
    case idle
    case loadingAsset
    case preparingContracts
    case ready
    case running
    case benchmarking

    var isBusy: Bool {
        switch self {
        case .loadingAsset, .preparingContracts, .running, .benchmarking:
            true
        case .idle, .ready:
            false
        }
    }
}
