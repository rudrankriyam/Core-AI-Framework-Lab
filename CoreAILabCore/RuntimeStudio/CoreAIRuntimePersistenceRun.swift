import Foundation

@MainActor
struct CoreAIRuntimePersistenceRun {
    let persistence: any CoreAIRunPersisting
    let start: CoreAIRuntimeRunStart
    var persistentRunID: UUID?
    var completedSummary: CoreAIRuntimeRunSummary?
}
