import Foundation

enum CoreAIFunctionBenchmarkError: LocalizedError, Equatable {
    case invalidWarmupCount(value: Int, allowed: ClosedRange<Int>)
    case invalidMeasuredRunCount(value: Int, allowed: ClosedRange<Int>)
    case missingTrials

    var errorDescription: String? {
        switch self {
        case .invalidWarmupCount(let value, let allowed):
            "Warmup runs must be between \(allowed.lowerBound) and \(allowed.upperBound); received \(value)."
        case .invalidMeasuredRunCount(let value, let allowed):
            "Measured runs must be between \(allowed.lowerBound) and \(allowed.upperBound); received \(value)."
        case .missingTrials:
            "A benchmark needs at least one measured trial."
        }
    }
}
