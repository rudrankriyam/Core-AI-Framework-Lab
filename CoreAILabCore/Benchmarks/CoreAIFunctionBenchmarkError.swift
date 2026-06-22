import Foundation

enum CoreAIFunctionBenchmarkError: LocalizedError, Equatable {
    case invalidWarmupCount(value: Int, allowed: ClosedRange<Int>)
    case invalidMeasuredRunCount(value: Int, allowed: ClosedRange<Int>)
    case missingTrials
    case artifactChangedSinceSpecialization

    var errorDescription: String? {
        switch self {
        case .invalidWarmupCount(let value, let allowed):
            "Warmup runs must be between \(allowed.lowerBound) and \(allowed.upperBound); received \(value)."
        case .invalidMeasuredRunCount(let value, let allowed):
            "Measured runs must be between \(allowed.lowerBound) and \(allowed.upperBound); received \(value)."
        case .missingTrials:
            "A benchmark needs at least one measured trial."
        case .artifactChangedSinceSpecialization:
            "The model artifact changed after specialization. Reopen and specialize the current bytes before benchmarking."
        }
    }
}
