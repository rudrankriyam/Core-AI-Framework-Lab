import Foundation

struct CoreAIBenchmarkEvidenceExecutionState: Codable, Sendable, Equatable {
    let specializationCacheState: String
    let functionInstanceState: String
    let inputReuseState: String
    let inferenceWarmupState: String
    let requestedWarmupRuns: Int
    let requestedMeasuredRuns: Int
    let stoppedEarly: Bool

    init(
        configuration: CoreAIFunctionBenchmarkConfiguration,
        loadedFromCache: Bool,
        stoppedEarly: Bool
    ) {
        specializationCacheState = loadedFromCache ? "cacheHit" : "cacheMiss"
        functionInstanceState = "freshlyLoaded"
        inputReuseState = "generatedOnceAndReused"
        inferenceWarmupState = configuration.warmupRuns > 0
            ? "warmedWithExcludedRuns"
            : "noWarmup"
        requestedWarmupRuns = configuration.warmupRuns
        requestedMeasuredRuns = configuration.measuredRuns
        self.stoppedEarly = stoppedEarly
    }
}
