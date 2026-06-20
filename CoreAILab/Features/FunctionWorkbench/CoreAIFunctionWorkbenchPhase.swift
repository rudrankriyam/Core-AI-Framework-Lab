import Foundation

enum CoreAIFunctionWorkbenchPhase: Sendable, Equatable {
    case idle
    case loadingAsset
    case preparingContracts
    case ready
    case running

    var isBusy: Bool {
        switch self {
        case .loadingAsset, .preparingContracts, .running:
            true
        case .idle, .ready:
            false
        }
    }
}
