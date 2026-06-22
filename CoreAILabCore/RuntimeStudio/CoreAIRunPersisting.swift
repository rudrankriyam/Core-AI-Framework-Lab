import Foundation

@MainActor
protocol CoreAIRunPersisting: AnyObject {
    func startRun(
        start: CoreAIRuntimeRunStart
    ) throws -> UUID

    func finishRun(
        persistentRunID: UUID,
        summary: CoreAIRuntimeRunSummary
    ) throws
}
