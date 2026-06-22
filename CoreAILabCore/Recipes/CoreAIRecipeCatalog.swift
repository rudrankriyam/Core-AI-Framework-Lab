import Foundation

public enum CoreAIRecipeTrustState: String, Codable, CaseIterable, Sendable {
    case bundledCurated
    case publisherReviewed
    case importedUntrusted

    public var displayName: String {
        switch self {
        case .bundledCurated:
            "Bundled and curated"
        case .publisherReviewed:
            "Publisher reviewed"
        case .importedUntrusted:
            "Imported and untrusted"
        }
    }
}

public enum CoreAIRecipeVerificationState: String, Codable, CaseIterable, Sendable {
    case notVerified
    case schemaValidated
    case fixturesValidated
    case hardwareValidated

    public var displayName: String {
        switch self {
        case .notVerified:
            "Not verified"
        case .schemaValidated:
            "Schema validated"
        case .fixturesValidated:
            "Fixtures validated"
        case .hardwareValidated:
            "Hardware validated"
        }
    }
}

public struct CoreAIRecipeCatalogEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let familyID: String
    public let revision: String
    public let displayName: String
    public let summary: String
    public let trustState: CoreAIRecipeTrustState
    public let verificationState: CoreAIRecipeVerificationState
    public let verificationNotes: String
    public let evidenceReference: String?

    public init(
        id: String,
        familyID: String,
        revision: String,
        displayName: String,
        summary: String,
        trustState: CoreAIRecipeTrustState,
        verificationState: CoreAIRecipeVerificationState,
        verificationNotes: String,
        evidenceReference: String? = nil
    ) {
        self.id = id
        self.familyID = familyID
        self.revision = revision
        self.displayName = displayName
        self.summary = summary
        self.trustState = trustState
        self.verificationState = verificationState
        self.verificationNotes = verificationNotes
        self.evidenceReference = evidenceReference
    }

    fileprivate func validate(path: String) throws {
        try CoreAIRecipeBundleValidation.requireNonempty(id, path: "\(path).id")
        try CoreAIRecipeBundleValidation.requireNonempty(
            familyID,
            path: "\(path).familyID"
        )
        try CoreAIRecipeBundleValidation.requireNonempty(
            revision,
            path: "\(path).revision"
        )
        try CoreAIRecipeBundleValidation.requireNonempty(
            displayName,
            path: "\(path).displayName"
        )
        try CoreAIRecipeBundleValidation.requireNonempty(
            summary,
            path: "\(path).summary"
        )
        try CoreAIRecipeBundleValidation.requireNonempty(
            verificationNotes,
            path: "\(path).verificationNotes"
        )
        if verificationState == .hardwareValidated {
            try CoreAIRecipeBundleValidation.requireNonempty(
                evidenceReference ?? "",
                path: "\(path).evidenceReference"
            )
        }
    }
}

public struct CoreAIRecipeCatalogIndex: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let entries: [CoreAIRecipeCatalogEntry]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        entries: [CoreAIRecipeCatalogEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CoreAIRecipeBundleError.unsupportedCatalogSchemaVersion(
                found: schemaVersion,
                supported: Self.currentSchemaVersion
            )
        }
        var identifiers = Set<String>()
        for (index, entry) in entries.enumerated() {
            try entry.validate(path: "catalog.entries[\(index)]")
            guard identifiers.insert(entry.id).inserted else {
                throw CoreAIRecipeBundleError.duplicateIdentifier(
                    path: "catalog.entries",
                    identifier: entry.id
                )
            }
        }
    }
}

public enum CoreAIRecipeCatalog {
    public static func loadCurated(bundle: Bundle = .main) throws -> CoreAIRecipeCatalogIndex {
        guard let url = curatedResourceURL(in: bundle) else {
            throw CoreAIRecipeBundleError.missingPayload("curated-recipes.json")
        }
        return try decodeCurated(Data(contentsOf: url))
    }

    public static func decodeCurated(_ data: Data) throws -> CoreAIRecipeCatalogIndex {
        let index = try JSONDecoder().decode(CoreAIRecipeCatalogIndex.self, from: data)
        try index.validate()
        return index
    }

    private static func curatedResourceURL(in bundle: Bundle) -> URL? {
        bundle.url(
            forResource: "curated-recipes",
            withExtension: "json",
            subdirectory: "Recipes"
        ) ?? bundle.url(
            forResource: "curated-recipes",
            withExtension: "json"
        )
    }
}
