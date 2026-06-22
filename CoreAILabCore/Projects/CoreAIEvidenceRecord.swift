import Foundation
import SwiftData

enum CoreAIEvidenceKind: String, Codable, CaseIterable, Sendable {
    case artifact
    case benchmark
    case diagnostic
    case log
    case metric
    case output
    case validation
}

@Model
final class CoreAIEvidenceRecord {
    @Attribute(.unique) private(set) var id: UUID = UUID()
    private(set) var schemaVersion: Int = 1
    private(set) var kindRawValue: String = CoreAIEvidenceKind.output.rawValue
    private(set) var label: String = ""
    private(set) var summary: String = ""
    private(set) var relativePath: String?
    private(set) var sha256Digest: String?
    private(set) var mediaType: String?
    private(set) var metadataData: Data = Data()
    private(set) var createdAt: Date = Date.now
    private(set) var project: LabProject?
    private(set) var run: CoreAIRunRecord?

    init(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        id: UUID = UUID(),
        schemaVersion: Int = 1,
        kind: CoreAIEvidenceKind,
        label: String,
        summary: String = "",
        relativePath: String? = nil,
        sha256Digest: String? = nil,
        mediaType: String? = nil,
        metadataData: Data = Data(),
        createdAt: Date = .now,
        project: LabProject? = nil,
        run: CoreAIRunRecord? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        kindRawValue = kind.rawValue
        self.label = label
        self.summary = summary
        self.relativePath = relativePath
        self.sha256Digest = sha256Digest
        self.mediaType = mediaType
        self.metadataData = metadataData
        self.createdAt = createdAt
        self.project = project
        self.run = run
    }

    var kind: CoreAIEvidenceKind? {
        CoreAIEvidenceKind(rawValue: kindRawValue)
    }

    func decodedMetadata() throws -> [String: String] {
        guard !metadataData.isEmpty else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: metadataData)
    }
}
