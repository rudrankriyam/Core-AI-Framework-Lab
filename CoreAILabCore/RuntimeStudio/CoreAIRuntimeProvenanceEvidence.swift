import Foundation

struct CoreAIRuntimeProvenanceEvidence: Equatable, Sendable {
    let id: UUID
    let label: String
    let summary: String
    let metadata: [String: String]
}
