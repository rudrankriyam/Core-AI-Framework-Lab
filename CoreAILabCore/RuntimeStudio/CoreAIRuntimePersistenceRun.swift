import Foundation

@MainActor
struct CoreAIRuntimePersistenceRun {
    let persistence: any CoreAIRunPersisting
    let persistentRunID: UUID
    var completedSummary: CoreAIRuntimeRunSummary?
}
