import Foundation

struct CoreAIRuntimeMetricEvidence: Equatable, Sendable {
    let id: UUID
    let label: String
    let summary: String
    let metadata: [String: String]
}
