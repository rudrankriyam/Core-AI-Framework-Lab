import Foundation

struct CoreAIDeviceDiagnostic: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let severity: CoreAIDeviceDiagnosticSeverity
    let category: CoreAIDeviceDiagnosticCategory
    let title: String
    let detail: String
}
