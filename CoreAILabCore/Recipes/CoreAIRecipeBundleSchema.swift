import Foundation

public enum CoreAIRecipeBundleError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case unsupportedCatalogSchemaVersion(found: Int, supported: Int)
    case missingValue(path: String)
    case invalidRelativePath(path: String, value: String)
    case invalidDigest(path: String, value: String)
    case invalidByteCount(path: String, value: Int64)
    case unknownKey(path: String)
    case duplicateIdentifier(path: String, identifier: String)
    case duplicatePath(String)
    case missingRecipeManifest(String)
    case missingPayload(String)
    case unexpectedPayload(String)
    case unsupportedPayload(String)
    case symbolicLink(String)
    case hashMismatch(path: String, expected: String, actual: String)
    case sizeMismatch(path: String, expected: Int64, actual: Int64)
    case familyMismatch(expected: String, actual: String)
    case unknownCodeReference(path: String)
    case codeReferenceRoleMismatch(path: String)
    case hiddenCodeReference(path: String)
    case codeExecutionNotApproved(referenceID: String)
    case destinationExists(String)
    case destinationInsideSource
    case sourceChangedDuringExport(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let found, let supported):
            "The recipe bundle uses schema version \(found); this build supports version \(supported)."
        case .unsupportedCatalogSchemaVersion(let found, let supported):
            "The recipe catalog uses schema version \(found); this build supports version \(supported)."
        case .missingValue(let path):
            "\(path) must not be empty."
        case .invalidRelativePath(let path, let value):
            "\(path) must be a safe relative path, but found \(value)."
        case .invalidDigest(let path, let value):
            "\(path) must be a lowercase 64-character SHA-256 digest, but found \(value)."
        case .invalidByteCount(let path, let value):
            "\(path) must be zero or greater, but found \(value)."
        case .unknownKey(let path):
            "The recipe bundle contains an unknown field at \(path)."
        case .duplicateIdentifier(let path, let identifier):
            "\(path) contains the duplicate identifier \(identifier)."
        case .duplicatePath(let path):
            "The recipe bundle declares the path \(path) more than once."
        case .missingRecipeManifest(let path):
            "The recipe bundle does not declare its recipe manifest at \(path)."
        case .missingPayload(let path):
            "The recipe bundle is missing the declared payload \(path)."
        case .unexpectedPayload(let path):
            "The recipe bundle contains the undeclared payload \(path)."
        case .unsupportedPayload(let path):
            "The recipe bundle payload \(path) is not a regular file."
        case .symbolicLink(let path):
            "Recipe bundles cannot contain symbolic links: \(path)."
        case .hashMismatch(let path, let expected, let actual):
            "The SHA-256 digest for \(path) was \(actual), not the declared \(expected)."
        case .sizeMismatch(let path, let expected, let actual):
            "The byte count for \(path) was \(actual), not the declared \(expected)."
        case .familyMismatch(let expected, let actual):
            "The recipe belongs to family \(actual), not the expected family \(expected)."
        case .unknownCodeReference(let path):
            "The code reference \(path) is not a declared payload."
        case .codeReferenceRoleMismatch(let path):
            "The executable role and language do not agree for \(path)."
        case .hiddenCodeReference(let path):
            "The executable payload \(path) must have an explicit code reference."
        case .codeExecutionNotApproved(let referenceID):
            "Code execution has not been approved for \(referenceID)."
        case .destinationExists(let path):
            "The recipe bundle destination already exists: \(path)."
        case .destinationInsideSource:
            "The recipe bundle destination must be outside the authoring source root."
        case .sourceChangedDuringExport(let path):
            "The recipe source changed while \(path) was being exported."
        }
    }
}

public enum CoreAIRecipeBundleFileRole: String, Codable, CaseIterable, Sendable {
    case recipeManifest
    case validationFixture
    case documentation
    case data
    case pythonSource
    case swiftSource
    case customCode

    public var requiresExecutionApproval: Bool {
        switch self {
        case .pythonSource, .swiftSource, .customCode:
            true
        case .recipeManifest, .validationFixture, .documentation, .data:
            false
        }
    }
}

public enum CoreAIRecipeCodeLanguage: String, Codable, CaseIterable, Sendable {
    case python
    case swift
    case custom
}

public struct CoreAIRecipeBundleProvenance: Codable, Equatable, Sendable {
    public let sourceRepository: String
    public let sourceRevision: String
    public let license: String
    public let author: String

    public init(
        sourceRepository: String,
        sourceRevision: String,
        license: String,
        author: String
    ) {
        self.sourceRepository = sourceRepository
        self.sourceRevision = sourceRevision
        self.license = license
        self.author = author
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceRepository
        case sourceRevision
        case license
        case author
    }

    public init(from decoder: any Decoder) throws {
        try CoreAIRecipeBundleValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: CodingKeys.allCases.map(\.rawValue),
            path: "recipeBundle.provenance"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceRepository = try container.decode(String.self, forKey: .sourceRepository)
        sourceRevision = try container.decode(String.self, forKey: .sourceRevision)
        license = try container.decode(String.self, forKey: .license)
        author = try container.decode(String.self, forKey: .author)
    }

    fileprivate func validate() throws {
        try CoreAIRecipeBundleValidation.requireNonempty(
            sourceRepository,
            path: "provenance.sourceRepository"
        )
        try CoreAIRecipeBundleValidation.requireNonempty(
            sourceRevision,
            path: "provenance.sourceRevision"
        )
        try CoreAIRecipeBundleValidation.requireNonempty(
            license,
            path: "provenance.license"
        )
        try CoreAIRecipeBundleValidation.requireNonempty(
            author,
            path: "provenance.author"
        )
    }
}

public struct CoreAIRecipeBundleFile: Codable, Equatable, Sendable {
    public let relativePath: String
    public let sha256: String
    public let byteCount: Int64
    public let role: CoreAIRecipeBundleFileRole

    public init(
        relativePath: String,
        sha256: String,
        byteCount: Int64,
        role: CoreAIRecipeBundleFileRole
    ) {
        self.relativePath = relativePath
        self.sha256 = sha256
        self.byteCount = byteCount
        self.role = role
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case relativePath
        case sha256
        case byteCount
        case role
    }

    public init(from decoder: any Decoder) throws {
        try CoreAIRecipeBundleValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: CodingKeys.allCases.map(\.rawValue),
            path: "recipeBundle.files[]"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        sha256 = try container.decode(String.self, forKey: .sha256)
        byteCount = try container.decode(Int64.self, forKey: .byteCount)
        role = try container.decode(CoreAIRecipeBundleFileRole.self, forKey: .role)
    }

    fileprivate func validate(path: String) throws {
        try CoreAIRecipeBundleValidation.requireSafeRelativePath(
            relativePath,
            path: "\(path).relativePath"
        )
        try CoreAIRecipeBundleValidation.requireDigest(
            sha256,
            path: "\(path).sha256"
        )
        guard byteCount >= 0 else {
            throw CoreAIRecipeBundleError.invalidByteCount(
                path: "\(path).byteCount",
                value: byteCount
            )
        }
    }
}

public struct CoreAIRecipeCodeReference: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let relativePath: String
    public let language: CoreAIRecipeCodeLanguage
    public let entryPoint: String

    public init(
        id: String,
        relativePath: String,
        language: CoreAIRecipeCodeLanguage,
        entryPoint: String
    ) {
        self.id = id
        self.relativePath = relativePath
        self.language = language
        self.entryPoint = entryPoint
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case relativePath
        case language
        case entryPoint
    }

    public init(from decoder: any Decoder) throws {
        try CoreAIRecipeBundleValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: CodingKeys.allCases.map(\.rawValue),
            path: "recipeBundle.codeReferences[]"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        language = try container.decode(CoreAIRecipeCodeLanguage.self, forKey: .language)
        entryPoint = try container.decode(String.self, forKey: .entryPoint)
    }

    fileprivate func validate(path: String) throws {
        try CoreAIRecipeBundleValidation.requireNonempty(id, path: "\(path).id")
        try CoreAIRecipeBundleValidation.requireSafeRelativePath(
            relativePath,
            path: "\(path).relativePath"
        )
        try CoreAIRecipeBundleValidation.requireNonempty(
            entryPoint,
            path: "\(path).entryPoint"
        )
    }
}

public struct CoreAIRecipeBundleManifest: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1
    public static let fileName = "recipe-bundle.json"

    public let schemaVersion: Int
    public let id: String
    public let familyID: String
    public let revision: String
    public let displayName: String
    public let summary: String
    public let recipeManifestPath: String
    public let provenance: CoreAIRecipeBundleProvenance
    public let files: [CoreAIRecipeBundleFile]
    public let codeReferences: [CoreAIRecipeCodeReference]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String,
        familyID: String,
        revision: String,
        displayName: String,
        summary: String,
        recipeManifestPath: String,
        provenance: CoreAIRecipeBundleProvenance,
        files: [CoreAIRecipeBundleFile],
        codeReferences: [CoreAIRecipeCodeReference] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.familyID = familyID
        self.revision = revision
        self.displayName = displayName
        self.summary = summary
        self.recipeManifestPath = recipeManifestPath
        self.provenance = provenance
        self.files = files
        self.codeReferences = codeReferences
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case id
        case familyID
        case revision
        case displayName
        case summary
        case recipeManifestPath
        case provenance
        case files
        case codeReferences
    }

    public init(from decoder: any Decoder) throws {
        try CoreAIRecipeBundleValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: CodingKeys.allCases.map(\.rawValue),
            path: "recipeBundle"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        familyID = try container.decode(String.self, forKey: .familyID)
        revision = try container.decode(String.self, forKey: .revision)
        displayName = try container.decode(String.self, forKey: .displayName)
        summary = try container.decode(String.self, forKey: .summary)
        recipeManifestPath = try container.decode(String.self, forKey: .recipeManifestPath)
        provenance = try container.decode(
            CoreAIRecipeBundleProvenance.self,
            forKey: .provenance
        )
        files = try container.decode([CoreAIRecipeBundleFile].self, forKey: .files)
        codeReferences = try container.decode(
            [CoreAIRecipeCodeReference].self,
            forKey: .codeReferences
        )
    }

    public var requiresCodeApproval: Bool {
        !codeReferences.isEmpty
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CoreAIRecipeBundleError.unsupportedSchemaVersion(
                found: schemaVersion,
                supported: Self.currentSchemaVersion
            )
        }
        try CoreAIRecipeBundleValidation.requireNonempty(id, path: "recipeBundle.id")
        try CoreAIRecipeBundleValidation.requireNonempty(
            familyID,
            path: "recipeBundle.familyID"
        )
        try CoreAIRecipeBundleValidation.requireNonempty(
            revision,
            path: "recipeBundle.revision"
        )
        try CoreAIRecipeBundleValidation.requireNonempty(
            displayName,
            path: "recipeBundle.displayName"
        )
        try CoreAIRecipeBundleValidation.requireNonempty(
            summary,
            path: "recipeBundle.summary"
        )
        try CoreAIRecipeBundleValidation.requireSafeRelativePath(
            recipeManifestPath,
            path: "recipeBundle.recipeManifestPath"
        )
        try provenance.validate()
        guard !files.isEmpty else {
            throw CoreAIRecipeBundleError.missingValue(path: "recipeBundle.files")
        }

        var paths = Set<String>()
        var filesByPath: [String: CoreAIRecipeBundleFile] = [:]
        for (index, file) in files.enumerated() {
            try file.validate(path: "recipeBundle.files[\(index)]")
            let normalizedPath = file.relativePath.precomposedStringWithCanonicalMapping
            guard normalizedPath != Self.fileName else {
                throw CoreAIRecipeBundleError.invalidRelativePath(
                    path: "recipeBundle.files[\(index)].relativePath",
                    value: file.relativePath
                )
            }
            guard paths.insert(normalizedPath).inserted else {
                throw CoreAIRecipeBundleError.duplicatePath(file.relativePath)
            }
            filesByPath[normalizedPath] = file
        }

        guard filesByPath[recipeManifestPath.precomposedStringWithCanonicalMapping]?.role
                == .recipeManifest else {
            throw CoreAIRecipeBundleError.missingRecipeManifest(recipeManifestPath)
        }

        var referenceIDs = Set<String>()
        var referencedCodePaths = Set<String>()
        for (index, reference) in codeReferences.enumerated() {
            try reference.validate(path: "recipeBundle.codeReferences[\(index)]")
            guard referenceIDs.insert(reference.id).inserted else {
                throw CoreAIRecipeBundleError.duplicateIdentifier(
                    path: "recipeBundle.codeReferences",
                    identifier: reference.id
                )
            }
            let normalizedPath = reference.relativePath.precomposedStringWithCanonicalMapping
            guard let file = filesByPath[normalizedPath] else {
                throw CoreAIRecipeBundleError.unknownCodeReference(
                    path: reference.relativePath
                )
            }
            guard Self.role(file.role, matches: reference.language) else {
                throw CoreAIRecipeBundleError.codeReferenceRoleMismatch(
                    path: reference.relativePath
                )
            }
            referencedCodePaths.insert(normalizedPath)
        }

        for file in files where file.role.requiresExecutionApproval {
            let normalizedPath = file.relativePath.precomposedStringWithCanonicalMapping
            guard referencedCodePaths.contains(normalizedPath) else {
                throw CoreAIRecipeBundleError.hiddenCodeReference(
                    path: file.relativePath
                )
            }
        }

        for file in files where !file.role.requiresExecutionApproval {
            let pathExtension = URL(filePath: file.relativePath)
                .pathExtension
                .lowercased()
            if CoreAIRecipeBundleValidation.executablePathExtensions.contains(pathExtension) {
                throw CoreAIRecipeBundleError.hiddenCodeReference(
                    path: file.relativePath
                )
            }
        }
    }

    private static func role(
        _ role: CoreAIRecipeBundleFileRole,
        matches language: CoreAIRecipeCodeLanguage
    ) -> Bool {
        switch (role, language) {
        case (.pythonSource, .python), (.swiftSource, .swift), (.customCode, .custom):
            true
        default:
            false
        }
    }
}

enum CoreAIRecipeBundleValidation {
    static let executablePathExtensions: Set<String> = [
        "bash", "cjs", "class", "command", "dylib", "fish", "jar", "js",
        "jsx", "lua", "metal", "metallib", "mjs", "php", "pl", "pm", "py",
        "pyc", "pyo", "pyw", "r", "rb", "sh", "so", "swift", "ts", "tsx",
        "wasm", "zsh"
    ]

    static func requireNonempty(_ value: String, path: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoreAIRecipeBundleError.missingValue(path: path)
        }
    }

    static func requireSafeRelativePath(_ value: String, path: String) throws {
        try requireNonempty(value, path: path)
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        let isUnsafe = value.hasPrefix("/")
            || value.hasPrefix("~")
            || value.contains("\\")
            || value != value.precomposedStringWithCanonicalMapping
            || components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        guard !isUnsafe else {
            throw CoreAIRecipeBundleError.invalidRelativePath(path: path, value: value)
        }
    }

    static func requireDigest(_ value: String, path: String) throws {
        let isValid = value.utf8.count == 64
            && value.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            }
        guard isValid else {
            throw CoreAIRecipeBundleError.invalidDigest(path: path, value: value)
        }
    }

    static func rejectUnknownKeys(
        from decoder: any Decoder,
        allowedKeys: [String],
        path: String
    ) throws {
        let container = try decoder.container(keyedBy: CoreAIRecipeBundleCodingKey.self)
        let allowedKeys = Set(allowedKeys)
        if let unknownKey = container.allKeys
            .map(\.stringValue)
            .filter({ !allowedKeys.contains($0) })
            .sorted()
            .first {
            throw CoreAIRecipeBundleError.unknownKey(path: "\(path).\(unknownKey)")
        }
    }
}

private struct CoreAIRecipeBundleCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
