import Foundation

enum CoreAIBenchmarkEvidenceError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidField(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Benchmark evidence schema version \(version) is not supported."
        case .invalidField(let field):
            "Benchmark evidence contains an invalid \(field)."
        }
    }
}
