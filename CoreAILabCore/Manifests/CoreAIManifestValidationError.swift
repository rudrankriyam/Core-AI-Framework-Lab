import Foundation

enum CoreAIManifestValidationError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(path: String, found: Int, supported: Int)
    case missingValue(path: String)
    case duplicateIdentifier(path: String, identifier: String)
    case invalidRelativePath(path: String, value: String)
    case invalidValue(path: String, reason: String)
    case unknownReference(path: String, identifier: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let path, let found, let supported):
            "\(path) uses schema version \(found); this build supports version \(supported)."
        case .missingValue(let path):
            "\(path) must not be empty."
        case .duplicateIdentifier(let path, let identifier):
            "\(path) contains the duplicate identifier \(identifier)."
        case .invalidRelativePath(let path, let value):
            "\(path) must be a safe relative path, but found \(value)."
        case .invalidValue(let path, let reason):
            "\(path) is invalid: \(reason)"
        case .unknownReference(let path, let identifier):
            "\(path) references the unknown identifier \(identifier)."
        }
    }
}

enum CoreAIManifestValidator {
    static func isValidIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              CharacterSet.letters.union(CharacterSet(charactersIn: "_")).contains(first)
        else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "_-./")
        )
        return value.unicodeScalars.allSatisfy(allowed.contains)
            && !value.contains("..")
            && !value.hasPrefix("/")
            && !value.hasSuffix("/")
    }

    static func requireCurrentSchemaVersion(
        _ found: Int,
        supported: Int,
        path: String
    ) throws {
        guard found == supported else {
            throw CoreAIManifestValidationError.unsupportedSchemaVersion(
                path: path,
                found: found,
                supported: supported
            )
        }
    }

    static func requireNonempty(_ value: String, path: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoreAIManifestValidationError.missingValue(path: path)
        }
    }

    static func requireUniqueIdentifiers<T>(
        _ values: [T],
        path: String,
        identifier: (T) -> String
    ) throws {
        var identifiers = Set<String>()
        for value in values {
            let valueIdentifier = identifier(value)
            guard identifiers.insert(valueIdentifier).inserted else {
                throw CoreAIManifestValidationError.duplicateIdentifier(
                    path: path,
                    identifier: valueIdentifier
                )
            }
        }
    }

    static func requireSafeRelativePath(_ value: String, path: String) throws {
        try requireNonempty(value, path: path)
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        let isUnsafe = value.hasPrefix("/")
            || value.hasPrefix("~")
            || value.contains("\\")
            || components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        guard !isUnsafe else {
            throw CoreAIManifestValidationError.invalidRelativePath(
                path: path,
                value: value
            )
        }
    }
}
