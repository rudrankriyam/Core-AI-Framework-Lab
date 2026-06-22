import Foundation

struct CoreAIResourceFolderSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let directories: [String]
    let files: [CoreAIResourceFileSnapshot]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        directories: [String],
        files: [CoreAIResourceFileSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.directories = directories
        self.files = files
    }

    var byteCount: Int64 {
        files.reduce(into: 0) { total, file in
            let (updated, overflow) = total.addingReportingOverflow(file.byteCount)
            total = overflow ? Int64.max : updated
        }
    }

    func validate() throws {
        try CoreAIManifestValidator.requireCurrentSchemaVersion(
            schemaVersion,
            supported: Self.currentSchemaVersion,
            path: "resourceSnapshot.schemaVersion"
        )
        guard directories == directories.sorted(), files == files.sorted(by: {
            $0.relativePath < $1.relativePath
        }) else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "resourceSnapshot",
                reason: "directory and file entries must be sorted by relative path"
            )
        }
        try CoreAIManifestValidator.requireUniqueIdentifiers(
            directories,
            path: "resourceSnapshot.directories",
            identifier: { $0 }
        )
        try CoreAIManifestValidator.requireUniqueIdentifiers(
            files,
            path: "resourceSnapshot.files",
            identifier: \CoreAIResourceFileSnapshot.relativePath
        )
        for (index, directory) in directories.enumerated() {
            try CoreAIManifestValidator.requireSafeRelativePath(
                directory,
                path: "resourceSnapshot.directories[\(index)]"
            )
        }
        for (index, file) in files.enumerated() {
            try file.validate(path: "resourceSnapshot.files[\(index)]")
        }
        var validatedByteCount: Int64 = 0
        for file in files {
            let (updatedByteCount, overflow) = validatedByteCount.addingReportingOverflow(
                file.byteCount
            )
            guard !overflow else {
                throw CoreAIManifestValidationError.invalidValue(
                    path: "resourceSnapshot.files",
                    reason: "combined byte count exceeds Int64"
                )
            }
            validatedByteCount = updatedByteCount
        }
        let directorySet = Set(directories)
        guard files.allSatisfy({ !directorySet.contains($0.relativePath) }) else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "resourceSnapshot",
                reason: "a path cannot be both a directory and a file"
            )
        }
        let fileSet = Set(files.map(\.relativePath))
        for relativePath in directories + files.map(\.relativePath) {
            let components = relativePath.split(separator: "/").map(String.init)
            guard components.count > 1 else { continue }
            var parentComponents: [String] = []
            for component in components.dropLast() {
                parentComponents.append(component)
                let parentPath = parentComponents.joined(separator: "/")
                guard directorySet.contains(parentPath),
                      !fileSet.contains(parentPath) else {
                    throw CoreAIManifestValidationError.invalidValue(
                        path: "resourceSnapshot",
                        reason: "\(relativePath) is missing the directory \(parentPath)"
                    )
                }
            }
        }
    }
}
