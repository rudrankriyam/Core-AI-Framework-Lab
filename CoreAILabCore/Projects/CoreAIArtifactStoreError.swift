import Foundation

enum CoreAIArtifactStoreError: LocalizedError, Equatable {
    case sourceMissing(String)
    case unsupportedItem(String)
    case symbolicLink(String)
    case sourceChangedDuringImport
    case corruptedStoredArtifact(String)
    case invalidStoredPath

    var errorDescription: String? {
        switch self {
        case .sourceMissing(let name):
            "The artifact \(name) no longer exists."
        case .unsupportedItem(let name):
            "\(name) is not a regular file or directory."
        case .symbolicLink(let path):
            "Symbolic links are not imported into project storage: \(path)"
        case .sourceChangedDuringImport:
            "The artifact changed while it was being imported. Try again after the producing process finishes."
        case .corruptedStoredArtifact(let digest):
            "The stored artifact for SHA-256 \(digest) failed its integrity check."
        case .invalidStoredPath:
            "The artifact metadata contains an invalid storage path."
        }
    }
}
