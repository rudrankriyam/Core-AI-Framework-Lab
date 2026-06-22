import Foundation

struct CoreAIRuntimeRunStart: Equatable, Sendable {
    let id: UUID
    let context: CoreAIRuntimeRunContext
    let modelIdentity: String
    let timingClass: CoreAIRuntimeTimingClass
    let selectedComparisonIdentity: CoreAIRuntimeComparisonIdentity?
    let startedAt: Date
}
