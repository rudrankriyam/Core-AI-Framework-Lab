import Foundation
import SwiftData

@Model
final class CoreAITargetProfileRecord {
    @Attribute(.unique) private(set) var id: UUID = UUID()
    private(set) var schemaVersion: Int = 1
    private(set) var targetIdentifier: String = ""
    private(set) var displayName: String = ""
    private(set) var platformRawValue: String = CoreAITargetPlatform.macOS.rawValue
    private(set) var preferredComputeUnitRawValue: String = CoreAIComputeUnitPreference.automatic.rawValue
    private(set) var manifestData: Data = Data()
    private(set) var createdAt: Date = Date.now
    private(set) var project: LabProject?

    @Relationship(deleteRule: .nullify, inverse: \CoreAIRunRecord.targetProfile)
    private(set) var runs: [CoreAIRunRecord] = []

    init(
        authorization _: CoreAIProjectDomainWriteAuthorization,
        id: UUID = UUID(),
        schemaVersion: Int = 1,
        targetIdentifier: String,
        displayName: String,
        platform: CoreAITargetPlatform,
        preferredComputeUnit: CoreAIComputeUnitPreference,
        manifestData: Data,
        createdAt: Date = .now,
        project: LabProject? = nil,
        runs: [CoreAIRunRecord] = []
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.targetIdentifier = targetIdentifier
        self.displayName = displayName
        platformRawValue = platform.rawValue
        preferredComputeUnitRawValue = preferredComputeUnit.rawValue
        self.manifestData = manifestData
        self.createdAt = createdAt
        self.project = project
        self.runs = runs
    }

    var platform: CoreAITargetPlatform? {
        CoreAITargetPlatform(rawValue: platformRawValue)
    }

    var preferredComputeUnit: CoreAIComputeUnitPreference? {
        CoreAIComputeUnitPreference(rawValue: preferredComputeUnitRawValue)
    }

    func decodedManifest() throws -> CoreAITargetManifest {
        let manifest = try JSONDecoder().decode(
            CoreAITargetManifest.self,
            from: manifestData
        )
        try manifest.validate()
        guard schemaVersion == 1,
              manifest.id == targetIdentifier,
              manifest.displayName == displayName,
              platformRawValue == manifest.platform.rawValue,
              preferredComputeUnitRawValue == manifest.preferredComputeUnit.rawValue else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "targetProfileRecord",
                reason: "stored snapshot metadata does not match its manifest"
            )
        }
        return manifest
    }
}
