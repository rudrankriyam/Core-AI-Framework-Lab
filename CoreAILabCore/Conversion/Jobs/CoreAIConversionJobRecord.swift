import Foundation

struct CoreAIConversionJobRecord: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let modelName: String
    let identity: CoreAIConversionJobIdentity
    let fingerprint: CoreAIConversionJobFingerprint
    let createdAt: Date
    let attempt: Int
    let state: CoreAIConversionJobState
    let updatedAt: Date
    let statusDetail: String?

    init(
        id: UUID = UUID(),
        identity: CoreAIConversionJobIdentity,
        createdAt: Date = .now,
        attempt: Int = 1,
        state: CoreAIConversionJobState = .queued,
        updatedAt: Date? = nil,
        statusDetail: String? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        modelName = identity.request.modelName
        self.identity = identity
        fingerprint = identity.fingerprint
        self.createdAt = createdAt
        self.attempt = attempt
        self.state = state
        self.updatedAt = updatedAt ?? createdAt
        self.statusDetail = statusDetail
    }

    func transitioning(
        to next: CoreAIConversionJobState,
        at date: Date,
        detail: String?
    ) throws -> Self {
        guard state.allowsTransition(to: next) else {
            throw CoreAIConversionJobStoreError.illegalTransition(from: state, to: next)
        }
        return Self(
            id: id,
            identity: identity,
            createdAt: createdAt,
            attempt: next == .queued ? attempt + 1 : attempt,
            state: next,
            updatedAt: date,
            statusDetail: detail
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CoreAIConversionJobStoreError.unsupportedSchema(schemaVersion)
        }
        let identity = try container.decode(CoreAIConversionJobIdentity.self, forKey: .identity)
        let storedModelName = try container.decode(String.self, forKey: .modelName)
        let storedFingerprint = try container.decode(
            CoreAIConversionJobFingerprint.self,
            forKey: .fingerprint
        )
        guard storedModelName == identity.request.modelName,
              storedFingerprint == identity.fingerprint else {
            throw CoreAIConversionJobStoreError.corruptRecord
        }
        self.schemaVersion = schemaVersion
        id = try container.decode(UUID.self, forKey: .id)
        modelName = storedModelName
        self.identity = identity
        fingerprint = storedFingerprint
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        attempt = try container.decode(Int.self, forKey: .attempt)
        state = try container.decode(CoreAIConversionJobState.self, forKey: .state)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        statusDetail = try container.decodeIfPresent(String.self, forKey: .statusDetail)
        guard attempt >= 1, updatedAt >= createdAt else {
            throw CoreAIConversionJobStoreError.corruptRecord
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case modelName
        case identity
        case fingerprint
        case createdAt
        case attempt
        case state
        case updatedAt
        case statusDetail
    }
}

struct CoreAIConversionJobLogEntry: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    enum Kind: String, Codable, Sendable {
        case lifecycle
        case standardOutput
        case diagnostic
    }

    let schemaVersion: Int
    let id: UUID
    let attempt: Int
    let sequence: Int64
    let createdAt: Date
    let kind: Kind
    let message: String

    init(
        id: UUID = UUID(),
        attempt: Int,
        sequence: Int64,
        createdAt: Date = .now,
        kind: Kind,
        message: String
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.attempt = attempt
        self.sequence = sequence
        self.createdAt = createdAt
        self.kind = kind
        self.message = message
    }
}

struct CoreAIConversionCheckpointArtifact: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case file
        case modelAsset
        case resourceBundle
    }

    enum DigestScheme: String, Codable, Sendable {
        case sha256FileV1
        case sha256TreeV1
    }

    let kind: Kind
    let digestScheme: DigestScheme
    let relativePath: String
    let sha256: String
    let byteCount: Int64
    let fileCount: Int

    init(
        kind: Kind = .modelAsset,
        digestScheme: DigestScheme = .sha256TreeV1,
        relativePath: String,
        sha256: String,
        byteCount: Int64,
        fileCount: Int = 1
    ) throws {
        guard Self.isSafeRelativePath(relativePath) else {
            throw CoreAIConversionJobStoreError.unsafeRelativePath(relativePath)
        }
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard sha256.utf8.count == 64,
              sha256.unicodeScalars.allSatisfy(hexadecimal.contains),
              byteCount >= 0,
              fileCount >= 0,
              (kind == .file) == (digestScheme == .sha256FileV1),
              kind != .file || fileCount == 1 else {
            throw CoreAIConversionJobStoreError.invalidCheckpointArtifact(relativePath)
        }
        self.kind = kind
        self.digestScheme = digestScheme
        self.relativePath = relativePath
        self.sha256 = sha256.lowercased()
        self.byteCount = byteCount
        self.fileCount = fileCount
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: container.decode(Kind.self, forKey: .kind),
            digestScheme: container.decode(DigestScheme.self, forKey: .digestScheme),
            relativePath: container.decode(String.self, forKey: .relativePath),
            sha256: container.decode(String.self, forKey: .sha256),
            byteCount: container.decode(Int64.self, forKey: .byteCount),
            fileCount: container.decode(Int.self, forKey: .fileCount)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(digestScheme, forKey: .digestScheme)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(sha256, forKey: .sha256)
        try container.encode(byteCount, forKey: .byteCount)
        try container.encode(fileCount, forKey: .fileCount)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case digestScheme
        case relativePath
        case sha256
        case byteCount
        case fileCount
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/") else { return false }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }
}

struct CoreAIConversionCheckpoint: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let jobID: UUID
    let gate: String
    let artifactRootPath: String
    let fingerprint: CoreAIConversionJobFingerprint
    let artifacts: [CoreAIConversionCheckpointArtifact]
    let createdAt: Date

    init(
        jobID: UUID,
        gate: String,
        artifactRootPath: String,
        fingerprint: CoreAIConversionJobFingerprint,
        artifacts: [CoreAIConversionCheckpointArtifact],
        createdAt: Date = .now
    ) throws {
        guard Self.isSafeGate(gate) else {
            throw CoreAIConversionJobStoreError.invalidCheckpointGate(gate)
        }
        guard artifactRootPath.hasPrefix("/"),
              URL(filePath: artifactRootPath).standardizedFileURL.path == artifactRootPath else {
            throw CoreAIConversionJobStoreError.unsafeRelativePath(artifactRootPath)
        }
        let sortedArtifacts = artifacts.sorted { $0.relativePath < $1.relativePath }
        guard Set(sortedArtifacts.map(\.relativePath)).count == sortedArtifacts.count else {
            throw CoreAIConversionJobStoreError.invalidCheckpointArtifact("duplicate path")
        }
        schemaVersion = Self.currentSchemaVersion
        self.jobID = jobID
        self.gate = gate
        self.artifactRootPath = artifactRootPath
        self.fingerprint = fingerprint
        self.artifacts = sortedArtifacts
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CoreAIConversionJobStoreError.unsupportedSchema(schemaVersion)
        }
        try self.init(
            jobID: container.decode(UUID.self, forKey: .jobID),
            gate: container.decode(String.self, forKey: .gate),
            artifactRootPath: container.decode(String.self, forKey: .artifactRootPath),
            fingerprint: container.decode(CoreAIConversionJobFingerprint.self, forKey: .fingerprint),
            artifacts: container.decode([CoreAIConversionCheckpointArtifact].self, forKey: .artifacts),
            createdAt: container.decode(Date.self, forKey: .createdAt)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(jobID, forKey: .jobID)
        try container.encode(gate, forKey: .gate)
        try container.encode(artifactRootPath, forKey: .artifactRootPath)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encode(artifacts, forKey: .artifacts)
        try container.encode(createdAt, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case jobID
        case gate
        case artifactRootPath
        case fingerprint
        case artifacts
        case createdAt
    }

    private static func isSafeGate(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return !value.isEmpty
            && value.utf8.count <= 80
            && value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

enum CoreAIConversionCheckpointReuseDecision: Equatable, Sendable {
    case reusable
    case gateChanged
    case requestChanged
    case environmentChanged
    case artifactsChanged
}

enum CoreAIConversionCheckpointReuseEvaluator {
    static func evaluate(
        _ checkpoint: CoreAIConversionCheckpoint,
        expectedGate: String,
        currentFingerprint: CoreAIConversionJobFingerprint,
        verifiedArtifacts: [CoreAIConversionCheckpointArtifact]
    ) -> CoreAIConversionCheckpointReuseDecision {
        guard checkpoint.gate == expectedGate else { return .gateChanged }
        guard checkpoint.fingerprint.requestSHA256 == currentFingerprint.requestSHA256 else {
            return .requestChanged
        }
        guard checkpoint.fingerprint.environmentSHA256 == currentFingerprint.environmentSHA256 else {
            return .environmentChanged
        }
        guard checkpoint.artifacts == verifiedArtifacts.sorted(by: { $0.relativePath < $1.relativePath }) else {
            return .artifactsChanged
        }
        return .reusable
    }
}
