import Foundation

struct CoreAIRuntimeRunSummary: Equatable, Identifiable, Sendable {
    let id: UUID
    let context: CoreAIRuntimeRunContext
    let modelIdentity: String
    let state: CoreAIRuntimeLifecycleState
    let timingClass: CoreAIRuntimeTimingClass
    let selectedComparisonIdentity: CoreAIRuntimeComparisonIdentity?
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Double?
    let summary: String
}
