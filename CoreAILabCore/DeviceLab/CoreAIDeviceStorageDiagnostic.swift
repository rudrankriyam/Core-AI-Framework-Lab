import Foundation

struct CoreAIDeviceStorageDiagnostic: Codable, Equatable, Identifiable, Sendable {
    let kind: CoreAIDeviceStorageDiagnosticKind
    let message: String

    var id: CoreAIDeviceStorageDiagnosticKind { kind }
}
