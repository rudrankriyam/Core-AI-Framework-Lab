import Foundation

enum CoreAICacheRemovalScope: Sendable, Equatable {
    case selectedProfile
    case allProfilesForAsset

    var title: String {
        switch self {
        case .selectedProfile:
            "Remove Selected Profile"
        case .allProfilesForAsset:
            "Remove All Profiles for This Asset"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .selectedProfile:
            "Core AI will specialize this compute profile again the next time it is used."
        case .allProfilesForAsset:
            "Core AI will remove every cached specialization associated with this source asset. Each profile will need to be specialized again."
        }
    }
}
