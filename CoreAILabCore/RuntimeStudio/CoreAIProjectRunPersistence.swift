import Foundation
import SwiftData

@MainActor
final class CoreAIProjectRunPersistence: CoreAIRunPersisting {
    private let project: LabProject
    private let modelContext: ModelContext
    private let controller: any CoreAIProjectRunWriting
    private var activeRuns: [UUID: CoreAIRunRecord] = [:]

    init(
        project: LabProject,
        modelContext: ModelContext,
        controller: any CoreAIProjectRunWriting = CoreAIProjectLibraryController()
    ) {
        self.project = project
        self.modelContext = modelContext
        self.controller = controller
    }

    func startRun(start: CoreAIRuntimeRunStart) throws -> UUID {
        let run = try controller.createRuntimeRun(
            in: project,
            recipeRevision: nil,
            provenanceEvidence: provenanceEvidence(for: start),
            modelContext: modelContext
        )
        activeRuns[run.id] = run
        return run.id
    }

    func finishRun(
        persistentRunID: UUID,
        summary: CoreAIRuntimeRunSummary
    ) throws {
        guard let run = activeRuns[persistentRunID] else {
            throw CoreAIProjectLibraryError.projectUnavailable
        }
        guard let endedAt = summary.endedAt else {
            throw CoreAIProjectLibraryError.terminalRunRequiresUpdate
        }
        try controller.finishRuntimeRun(
            run,
            status: persistedStatus(summary.state),
            summary: summary.summary,
            endedAt: endedAt,
            metricEvidence: metricEvidence(for: summary),
            modelContext: modelContext
        )
        activeRuns.removeValue(forKey: persistentRunID)
    }

    private func provenanceEvidence(
        for start: CoreAIRuntimeRunStart
    ) -> CoreAIRuntimeProvenanceEvidence {
        var metadata = [
            "experience_id": start.context.experienceID,
            "model_identifier": start.modelIdentity,
            "recipe_provenance": start.context.recipeProvenance.rawValue
        ]
        let evidenceSummary: String
        switch start.context.recipeProvenance {
        case .unattributed:
            evidenceSummary = "No recipe attribution was supplied for this runtime run."
        case .unverifiedIntent:
            metadata["intended_recipe_identifier"] = start.context.recipeIdentifier
            metadata["intended_recipe_revision"] = start.context.recipeRevision
            evidenceSummary = "The selected recipe is recorded as unverified intent because no artifact-bound recipe proof was supplied."
        }
        return CoreAIRuntimeProvenanceEvidence(
            id: UUID(),
            label: "\(start.context.experienceTitle) runtime provenance",
            summary: evidenceSummary,
            metadata: metadata
        )
    }

    private func metricEvidence(
        for summary: CoreAIRuntimeRunSummary
    ) -> CoreAIRuntimeMetricEvidence? {
        guard summary.state == .succeeded,
              let durationSeconds = summary.durationSeconds else {
            return nil
        }
        var metadata = [
            "duration_seconds": String(durationSeconds),
            "experience_id": summary.context.experienceID,
            "model_identifier": summary.modelIdentity,
            "recipe_provenance": summary.context.recipeProvenance.rawValue,
            "timing_class": summary.timingClass.rawValue
        ]
        switch summary.context.recipeProvenance {
        case .unattributed:
            break
        case .unverifiedIntent:
            metadata["intended_recipe_identifier"] = summary.context.recipeIdentifier
            metadata["intended_recipe_revision"] = summary.context.recipeRevision
        }
        if let comparison = summary.selectedComparisonIdentity {
            metadata["comparison_identity"] = comparison.id
        }
        return CoreAIRuntimeMetricEvidence(
            id: summary.id,
            label: "\(summary.context.experienceTitle) runtime timing",
            summary: "\(summary.timingClass.title) run completed in \(durationSeconds.formatted(.number.precision(.fractionLength(3)))) seconds.",
            metadata: metadata
        )
    }

    private func persistedStatus(_ state: CoreAIRuntimeLifecycleState) -> CoreAIRunStatus {
        switch state {
        case .canceled:
            .cancelled
        case .failed:
            .failed
        case .started:
            .running
        case .succeeded:
            .succeeded
        }
    }
}
