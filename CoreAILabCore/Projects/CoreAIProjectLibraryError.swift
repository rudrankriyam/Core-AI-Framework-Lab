import Foundation

enum CoreAIProjectLibraryError: LocalizedError, Equatable {
    case projectNameRequired
    case operationInProgress
    case projectUnavailable
    case artifactUnavailable
    case inconsistentArtifactRecord
    case domainRecordProjectMismatch
    case terminalRunRequiresUpdate
    case runStatusUnavailable
    case invalidRunStatusTransition(from: CoreAIRunStatus, to: CoreAIRunStatus)
    case evidenceLabelRequired
    case descriptorSourceMismatch
    case invalidSourceProvenance(String)
    case invalidSpecializationCacheRecord
    case modelAssetRequired

    var errorDescription: String? {
        switch self {
        case .projectNameRequired:
            "Enter a project name."
        case .operationInProgress:
            "Wait for the current artifact operation to finish."
        case .projectUnavailable:
            "The project is no longer available."
        case .artifactUnavailable:
            "The artifact is no longer available."
        case .inconsistentArtifactRecord:
            "The artifact metadata does not match its content-addressed storage path."
        case .domainRecordProjectMismatch:
            "The recipe, target, run, and evidence records must belong to the same project."
        case .terminalRunRequiresUpdate:
            "Create a pending or running run, then record its terminal status through updateRun."
        case .runStatusUnavailable:
            "The run has an invalid persisted status."
        case let .invalidRunStatusTransition(from, to):
            "A run cannot transition from \(from.rawValue) to \(to.rawValue)."
        case .evidenceLabelRequired:
            "Enter an evidence label."
        case .descriptorSourceMismatch:
            "The inspected descriptor does not belong to this stored artifact."
        case .invalidSourceProvenance(let reason):
            "The source provenance is invalid: \(reason)"
        case .invalidSpecializationCacheRecord:
            "The specialization cache record contains an unsupported configuration."
        case .modelAssetRequired:
            "This operation requires a stored Core AI model asset."
        }
    }
}
