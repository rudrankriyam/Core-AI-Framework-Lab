import Foundation

struct CoreAIRuntimeRunToken: Equatable, Sendable {
    let id: UUID
    let context: CoreAIRuntimeRunContext
    let modelIdentity: String
    let timingClass: CoreAIRuntimeTimingClass
    let selectedComparisonIdentity: CoreAIRuntimeComparisonIdentity?
    let startedAt: Date
    let startedMonotonicSeconds: TimeInterval
}
