import Foundation

struct CoreAIAssetDeliverySlice: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let downloadByteCount: UInt64
    let installedByteCount: UInt64
    let deliveryMode: CoreAIAssetDeliveryMode

    func validate(path: String = "slice") throws {
        try CoreAIManifestValidator.requireNonempty(id, path: "\(path).id")
        try CoreAIManifestValidator.requireNonempty(
            displayName,
            path: "\(path).displayName"
        )
        guard downloadByteCount > 0 else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "\(path).downloadByteCount",
                reason: "an asset slice must download at least one byte"
            )
        }
        guard installedByteCount > 0 else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "\(path).installedByteCount",
                reason: "an installed asset slice must contain at least one byte"
            )
        }
    }
}
