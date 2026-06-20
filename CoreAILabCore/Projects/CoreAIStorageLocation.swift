import Foundation

enum CoreAIStorageLocation {
    nonisolated static let rootURL = URL.applicationSupportDirectory
        .appending(path: "Core AI Lab", directoryHint: .isDirectory)

    nonisolated static let projectStoreURL = rootURL
        .appending(path: "Projects.store", directoryHint: .notDirectory)

    nonisolated static let artifactRootURL = rootURL
        .appending(path: "Artifacts", directoryHint: .isDirectory)
}
