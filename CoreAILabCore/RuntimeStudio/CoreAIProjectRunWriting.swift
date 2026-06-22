import Foundation
import SwiftData

@MainActor
protocol CoreAIProjectRunWriting: AnyObject {
    func createRuntimeRun(
        id: UUID,
        in project: LabProject,
        recipeRevision: CoreAIRecipeRevisionRecord?,
        provenanceEvidence: CoreAIRuntimeProvenanceEvidence,
        modelContext: ModelContext
    ) throws -> CoreAIRunRecord

    func finishRuntimeRun(
        _ run: CoreAIRunRecord,
        status: CoreAIRunStatus,
        summary: String,
        endedAt: Date,
        metricEvidence: CoreAIRuntimeMetricEvidence?,
        modelContext: ModelContext
    ) throws

    @discardableResult
    func recoverInterruptedRuntimeRuns(
        in project: LabProject,
        endedAt: Date,
        modelContext: ModelContext
    ) throws -> Int
}
