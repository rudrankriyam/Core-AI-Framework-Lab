import Foundation

enum CoreAIDeviceStorageDiagnosticKind: String, Codable, CaseIterable, Sendable {
    case appDownloadBudgetExceeded
    case availableStorageExceeded
}
