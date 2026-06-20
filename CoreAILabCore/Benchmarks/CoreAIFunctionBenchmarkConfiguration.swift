import Foundation

struct CoreAIFunctionBenchmarkConfiguration: Sendable, Equatable {
    static let warmupRange = 0...10
    static let measuredRunRange = 1...100

    var warmupRuns = 1
    var measuredRuns = 5

    func validate() throws {
        guard Self.warmupRange.contains(warmupRuns) else {
            throw CoreAIFunctionBenchmarkError.invalidWarmupCount(
                value: warmupRuns,
                allowed: Self.warmupRange
            )
        }
        guard Self.measuredRunRange.contains(measuredRuns) else {
            throw CoreAIFunctionBenchmarkError.invalidMeasuredRunCount(
                value: measuredRuns,
                allowed: Self.measuredRunRange
            )
        }
    }
}
