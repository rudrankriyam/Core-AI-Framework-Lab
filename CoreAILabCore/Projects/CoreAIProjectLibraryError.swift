import Foundation

enum CoreAIProjectLibraryError: LocalizedError, Equatable {
    case projectNameRequired
    case operationInProgress
    case projectUnavailable
    case artifactUnavailable
    case inconsistentArtifactRecord

    var errorDescription: String? {
        switch self {
        case .projectNameRequired:
            "Enter a project name."
        case .operationInProgress:
            "Wait for the current artifact operation to finish."
        case .projectUnavailable:
            "The project is no longer available."
        case .artifactUnavailable:
            "The artifact is no longer available."
        case .inconsistentArtifactRecord:
            "The artifact metadata does not match its content-addressed storage path."
        }
    }
}
