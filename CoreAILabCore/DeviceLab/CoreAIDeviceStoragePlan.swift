import Foundation

struct CoreAIDeviceStoragePlan: Codable, Equatable, Sendable {
    let appDownloadBytes: UInt64
    let onDemandDownloadBytes: UInt64
    let installedAssetBytes: UInt64
    let peakRequiredDeviceBytes: UInt64
    let diagnostics: [CoreAIDeviceStorageDiagnostic]

    var fitsBudgets: Bool {
        diagnostics.isEmpty
    }
}
