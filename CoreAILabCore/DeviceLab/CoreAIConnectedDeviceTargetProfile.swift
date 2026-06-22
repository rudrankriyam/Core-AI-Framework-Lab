import Foundation

struct CoreAIConnectedDeviceTargetProfile: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: String
    let displayName: String
    let platform: CoreAITargetPlatform
    let device: CoreAIDeviceFacts
    let minimumOSVersion: String
    let preferredComputeUnit: CoreAIComputeUnitPreference
    let expectsFrequentReshapes: Bool
    let contextTokenLimit: Int?
    let staticInputShapes: [String: [Int]]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String,
        displayName: String,
        platform: CoreAITargetPlatform = .iOS,
        device: CoreAIDeviceFacts,
        minimumOSVersion: String,
        preferredComputeUnit: CoreAIComputeUnitPreference,
        expectsFrequentReshapes: Bool,
        contextTokenLimit: Int?,
        staticInputShapes: [String: [Int]]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.platform = platform
        self.device = device
        self.minimumOSVersion = minimumOSVersion
        self.preferredComputeUnit = preferredComputeUnit
        self.expectsFrequentReshapes = expectsFrequentReshapes
        self.contextTokenLimit = contextTokenLimit
        self.staticInputShapes = staticInputShapes
    }

    func validate(path: String = "connectedDeviceTarget") throws {
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
        guard platform == .iOS else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "\(path).platform",
                reason: "a connected iPhone target must use the iOS platform"
            )
        }
        try CoreAIManifestValidator.requireNonempty(
            minimumOSVersion,
            path: "\(path).minimumOSVersion"
        )
        try device.validate(path: "\(path).device")
        try CoreAIDeviceConfigurationIdentity.validateShapeConfiguration(
            contextTokens: contextTokenLimit,
            staticInputShapes: staticInputShapes,
            path: path
        )
    }
}
