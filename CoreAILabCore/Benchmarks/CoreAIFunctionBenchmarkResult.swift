import Foundation

struct CoreAIFunctionBenchmarkResult: Sendable, Equatable {
    let functionName: String
    let functionLoadDuration: Duration
    let inputPreparationDuration: Duration
    let warmupDurations: [Duration]
    let trials: [CoreAIBenchmarkTrial]
    let statistics: CoreAIBenchmarkStatistics
    let outputs: [CoreAIFunctionOutputSummary]
    let environment: CoreAIBenchmarkEnvironment
}
