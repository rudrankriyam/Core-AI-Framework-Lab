import Foundation

struct CoreAIExportChecksumManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let files: [File]

    init(files: [File]) {
        schemaVersion = Self.currentSchemaVersion
        self.files = files.sorted {
            CoreAIExportPath.isOrderedBefore($0.relativePath, $1.relativePath)
        }
    }

    struct File: Codable, Equatable, Sendable {
        let relativePath: String
        let sha256: String
        let byteCount: Int64
    }
}
