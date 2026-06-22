import Foundation

enum CoreAITargetPlatform: String, Codable, CaseIterable, Sendable {
    case iOS
    case macOS
}

enum CoreAIComputeUnitPreference: String, Codable, CaseIterable, Sendable {
    case automatic
    case cpu
    case gpu
    case neuralEngine
}

struct CoreAITargetManifest: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: String
    let displayName: String
    let platform: CoreAITargetPlatform
    let minimumOSVersion: String
    let preferredComputeUnit: CoreAIComputeUnitPreference
    let expectsFrequentReshapes: Bool

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String,
        displayName: String,
        platform: CoreAITargetPlatform,
        minimumOSVersion: String,
        preferredComputeUnit: CoreAIComputeUnitPreference,
        expectsFrequentReshapes: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.platform = platform
        self.minimumOSVersion = minimumOSVersion
        self.preferredComputeUnit = preferredComputeUnit
        self.expectsFrequentReshapes = expectsFrequentReshapes
    }

    func validate(path: String = "target") throws {
        try CoreAIManifestValidator.requireCurrentSchemaVersion(
            schemaVersion,
            supported: Self.currentSchemaVersion,
            path: "\(path).schemaVersion"
        )
        try CoreAIManifestValidator.requireNonempty(id, path: "\(path).id")
        try CoreAIManifestValidator.requireNonempty(
            displayName,
            path: "\(path).displayName"
        )
        try CoreAIManifestValidator.requireNonempty(
            minimumOSVersion,
            path: "\(path).minimumOSVersion"
        )
    }
}
