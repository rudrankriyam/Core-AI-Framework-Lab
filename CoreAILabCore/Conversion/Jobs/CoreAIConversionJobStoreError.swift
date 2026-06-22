import Foundation

enum CoreAIConversionJobStoreError: LocalizedError, Equatable {
    case jobNotFound(UUID)
    case unsupportedSchema(Int)
    case illegalTransition(from: CoreAIConversionJobState, to: CoreAIConversionJobState)
    case terminalJobCannotAppendLog(UUID)
    case corruptLog(UUID)
    case corruptRecord
    case invalidCheckpointGate(String)
    case invalidCheckpointArtifact(String)
    case checkpointFingerprintMismatch
    case incompleteIdentity(String)
    case unsafeRelativePath(String)
    case unsafeStoreItem(String)
    case artifactVerificationFailed(String)
    case artifactChangedDuringVerification(String)

    var errorDescription: String? {
        switch self {
        case .jobNotFound(let id):
            "Conversion job \(id.uuidString) is unavailable."
        case .unsupportedSchema(let version):
            "Conversion job schema \(version) is not supported."
        case .illegalTransition(let current, let next):
            "A conversion job cannot move from \(current.rawValue) to \(next.rawValue)."
        case .terminalJobCannotAppendLog(let id):
            "Conversion job \(id.uuidString) is terminal and cannot accept more log entries."
        case .corruptLog(let id):
            "The structured log for conversion job \(id.uuidString) is invalid."
        case .corruptRecord:
            "A conversion job record failed its stored identity invariants."
        case .invalidCheckpointGate(let gate):
            "Conversion checkpoint gate \(gate) is invalid."
        case .invalidCheckpointArtifact(let path):
            "Conversion checkpoint artifact \(path) has invalid evidence."
        case .checkpointFingerprintMismatch:
            "The conversion checkpoint does not belong to this job fingerprint."
        case .incompleteIdentity(let field):
            "The conversion job is missing a stable \(field) identity."
        case .unsafeRelativePath(let path):
            "Conversion checkpoint artifact path \(path) is unsafe."
        case .unsafeStoreItem(let name):
            "Conversion job store item \(name) is not a safe regular file or directory."
        case .artifactVerificationFailed(let path):
            "Conversion checkpoint artifact \(path) could not be verified without following links."
        case .artifactChangedDuringVerification(let path):
            "Conversion checkpoint artifact \(path) changed while it was being verified."
        }
    }
}
