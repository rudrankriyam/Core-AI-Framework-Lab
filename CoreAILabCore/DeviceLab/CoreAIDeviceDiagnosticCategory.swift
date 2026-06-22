import Foundation

enum CoreAIDeviceDiagnosticCategory: String, Codable, CaseIterable, Sendable {
    case context
    case shape
    case precision
    case layout
    case projection
    case unsupportedOperation
    case specialization
    case inference
    case placement
}
