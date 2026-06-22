import Foundation

struct CoreAIDeviceStoragePlanRequest: Codable, Equatable, Sendable {
    let slices: [CoreAIAssetDeliverySlice]
    let appDownloadBudgetBytes: UInt64
    let availableDeviceBytes: UInt64
    let temporaryWorkingBytes: UInt64

    func validate(path: String = "storageRequest") throws {
        guard !slices.isEmpty else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "\(path).slices",
                reason: "at least one asset slice is required"
            )
        }
        try CoreAIManifestValidator.requireUniqueIdentifiers(
            slices,
            path: "\(path).slices",
            identifier: \CoreAIAssetDeliverySlice.id
        )
        for (index, slice) in slices.enumerated() {
            try slice.validate(path: "\(path).slices[\(index)]")
        }
    }
}
