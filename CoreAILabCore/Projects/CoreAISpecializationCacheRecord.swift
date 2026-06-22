import Foundation
import SwiftData

@Model
final class CoreAISpecializationCacheRecord {
    @Attribute(.unique) private(set) var id: UUID
    @Attribute(.unique) private(set) var identityKey: String?
    private(set) var profileRawValue: String
    private(set) var expectFrequentReshapes: Bool
    private(set) var createdAt: Date
    private(set) var lastUsedAt: Date
    private(set) var wasLoadedFromCache: Bool
    private(set) var project: LabProject?
    private(set) var artifactLink: ProjectArtifactLink?

    init(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        id: UUID = UUID(),
        configuration: CoreAISpecializationConfiguration,
        createdAt: Date = .now,
        lastUsedAt: Date = .now,
        wasLoadedFromCache: Bool,
        project: LabProject,
        artifactLink: ProjectArtifactLink
    ) {
        self.id = id
        identityKey = Self.identityKey(
            artifactLinkID: artifactLink.id,
            configuration: configuration
        )
        profileRawValue = configuration.profile.rawValue
        expectFrequentReshapes = configuration.expectFrequentReshapes
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.wasLoadedFromCache = wasLoadedFromCache
        self.project = project
        self.artifactLink = artifactLink
    }

    var configuration: CoreAISpecializationConfiguration? {
        guard let profile = CoreAISpecializationProfile(rawValue: profileRawValue) else {
            return nil
        }
        return CoreAISpecializationConfiguration(
            profile: profile,
            expectFrequentReshapes: expectFrequentReshapes
        )
    }

    var configurationTitle: String {
        guard let configuration else { return "Unknown configuration" }
        let reshapeTitle = configuration.expectFrequentReshapes
            ? "frequent reshapes"
            : "stable shapes"
        return "\(configuration.profile.title), \(reshapeTitle)"
    }

    static func identityKey(
        artifactLinkID: UUID,
        configuration: CoreAISpecializationConfiguration
    ) -> String {
        [
            artifactLinkID.uuidString.lowercased(),
            configuration.profile.rawValue,
            configuration.expectFrequentReshapes ? "reshape" : "stable"
        ].joined(separator: ":")
    }

    func markUsed(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        identityKey: String,
        wasLoadedFromCache: Bool
    ) {
        self.identityKey = identityKey
        lastUsedAt = .now
        self.wasLoadedFromCache = wasLoadedFromCache
    }
}
