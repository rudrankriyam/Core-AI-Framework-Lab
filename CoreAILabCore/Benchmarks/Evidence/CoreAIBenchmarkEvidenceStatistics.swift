import Foundation

struct CoreAIBenchmarkEvidenceStatistics: Codable, Sendable, Equatable {
    let minimum: CoreAIBenchmarkEvidenceTiming
    let median: CoreAIBenchmarkEvidenceTiming
    let mean: CoreAIBenchmarkEvidenceTiming
    let maximum: CoreAIBenchmarkEvidenceTiming
    let standardDeviation: CoreAIBenchmarkEvidenceTiming
    let runsPerSecond: Double
    let p95: CoreAIBenchmarkEvidenceTiming?

    init(statistics: CoreAIBenchmarkStatistics) {
        minimum = CoreAIBenchmarkEvidenceTiming(duration: statistics.minimum)
        median = CoreAIBenchmarkEvidenceTiming(duration: statistics.median)
        mean = CoreAIBenchmarkEvidenceTiming(duration: statistics.mean)
        maximum = CoreAIBenchmarkEvidenceTiming(duration: statistics.maximum)
        standardDeviation = CoreAIBenchmarkEvidenceTiming(
            duration: statistics.standardDeviation
        )
        runsPerSecond = statistics.runsPerSecond
        p95 = statistics.p95.map {
            CoreAIBenchmarkEvidenceTiming(duration: $0)
        }
    }
}
