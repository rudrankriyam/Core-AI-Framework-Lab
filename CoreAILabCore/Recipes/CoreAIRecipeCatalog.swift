import CryptoKit
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
    public let recipeManifestReference: String
    public let recipeManifestSHA256: String
    public let trustState: CoreAIRecipeTrustState
    public let verificationState: CoreAIRecipeVerificationState
    public let verificationNotes: String
    public let evidenceReference: String?
    public let evidenceSHA256: String?

    public init(
        id: String,
        familyID: String,
        revision: String,
        displayName: String,
        summary: String,
        recipeManifestReference: String,
        recipeManifestSHA256: String,
        trustState: CoreAIRecipeTrustState,
        verificationState: CoreAIRecipeVerificationState,
        verificationNotes: String,
        evidenceReference: String? = nil,
        evidenceSHA256: String? = nil
    ) {
        self.id = id
        self.familyID = familyID
        self.revision = revision
        self.displayName = displayName
        self.summary = summary
        self.recipeManifestReference = recipeManifestReference
        self.recipeManifestSHA256 = recipeManifestSHA256
        self.trustState = trustState
        self.verificationState = verificationState
        self.verificationNotes = verificationNotes
        self.evidenceReference = evidenceReference
        self.evidenceSHA256 = evidenceSHA256
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case familyID
        case revision
        case displayName
        case summary
        case recipeManifestReference
        case recipeManifestSHA256
        case trustState
        case verificationState
        case verificationNotes
        case evidenceReference
        case evidenceSHA256
    }

    public init(from decoder: any Decoder) throws {
        try CoreAIRecipeBundleValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: CodingKeys.allCases.map(\.rawValue),
            path: "catalog.entries[]"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        familyID = try container.decode(String.self, forKey: .familyID)
        revision = try container.decode(String.self, forKey: .revision)
        displayName = try container.decode(String.self, forKey: .displayName)
        summary = try container.decode(String.self, forKey: .summary)
        recipeManifestReference = try container.decode(
            String.self,
            forKey: .recipeManifestReference
        )
        recipeManifestSHA256 = try container.decode(
            String.self,
            forKey: .recipeManifestSHA256
        )
        trustState = try container.decode(CoreAIRecipeTrustState.self, forKey: .trustState)
        verificationState = try container.decode(
            CoreAIRecipeVerificationState.self,
            forKey: .verificationState
        )
        verificationNotes = try container.decode(String.self, forKey: .verificationNotes)
        evidenceReference = try container.decodeIfPresent(
            String.self,
            forKey: .evidenceReference
        )
        evidenceSHA256 = try container.decodeIfPresent(String.self, forKey: .evidenceSHA256)
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
        try CoreAIRecipeBundleValidation.requireSafeRelativePath(
            recipeManifestReference,
            path: "\(path).recipeManifestReference"
        )
        try CoreAIRecipeBundleValidation.requireDigest(
            recipeManifestSHA256,
            path: "\(path).recipeManifestSHA256"
        )
        try CoreAIRecipeBundleValidation.requireNonempty(
            verificationNotes,
            path: "\(path).verificationNotes"
        )
        if verificationState != .notVerified
            || evidenceReference != nil
            || evidenceSHA256 != nil {
            try CoreAIRecipeBundleValidation.requireSafeRelativePath(
                evidenceReference ?? "",
                path: "\(path).evidenceReference"
            )
            try CoreAIRecipeBundleValidation.requireDigest(
                evidenceSHA256 ?? "",
                path: "\(path).evidenceSHA256"
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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case entries
    }

    public init(from decoder: any Decoder) throws {
        try CoreAIRecipeBundleValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: CodingKeys.allCases.map(\.rawValue),
            path: "catalog"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        entries = try container.decode([CoreAIRecipeCatalogEntry].self, forKey: .entries)
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

    public func validateReferencedDigests(at rootURL: URL) throws {
        try validate()
        for entry in entries {
            try Self.validateDigest(
                entry.recipeManifestSHA256,
                reference: entry.recipeManifestReference,
                rootURL: rootURL
            )
            if entry.verificationState != .notVerified {
                try Self.validateDigest(
                    entry.evidenceSHA256 ?? "",
                    reference: entry.evidenceReference ?? "",
                    rootURL: rootURL
                )
            }
        }
    }

    private static func validateDigest(
        _ expectedDigest: String,
        reference: String,
        rootURL: URL
    ) throws {
        try CoreAIRecipeBundleValidation.requireSafeRelativePath(
            reference,
            path: "catalog.reference"
        )
        try CoreAIRecipeBundleValidation.requireDigest(
            expectedDigest,
            path: "catalog.referenceSHA256"
        )
        let resolvedRootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let referenceURL = rootURL.appending(path: reference)
        let referenceValues = try referenceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        if referenceValues.isSymbolicLink == true {
            throw CoreAIRecipeBundleError.symbolicLink(reference)
        }
        guard referenceValues.isRegularFile == true else {
            throw CoreAIRecipeBundleError.missingPayload(reference)
        }
        let resolvedReferenceURL = referenceURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard resolvedReferenceURL.path.hasPrefix(resolvedRootURL.path + "/") else {
            throw CoreAIRecipeBundleError.invalidRelativePath(
                path: "catalog.reference",
                value: reference
            )
        }
        let actualDigest = CoreAIHexadecimal.lowercase(
            SHA256.hash(data: try Data(contentsOf: resolvedReferenceURL))
        )
        guard actualDigest == expectedDigest else {
            throw CoreAIRecipeBundleError.hashMismatch(
                path: reference,
                expected: expectedDigest,
                actual: actualDigest
            )
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
