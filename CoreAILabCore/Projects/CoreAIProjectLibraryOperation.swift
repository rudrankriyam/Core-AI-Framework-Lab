import Foundation

enum CoreAIProjectLibraryOperation: Equatable, Sendable {
    case importingArtifact
    case removingArtifact
    case deletingProject
    case managingSpecializationCache

    var title: String {
        switch self {
        case .importingArtifact:
            "Hashing and storing artifact…"
        case .removingArtifact:
            "Removing project artifact…"
        case .deletingProject:
            "Deleting project…"
        case .managingSpecializationCache:
            "Updating Core AI cache…"
        }
    }

    var systemImage: String {
        switch self {
        case .importingArtifact:
            "square.and.arrow.down"
        case .removingArtifact:
            "trash"
        case .deletingProject:
            "folder.badge.minus"
        case .managingSpecializationCache:
            "cpu"
        }
    }
}
