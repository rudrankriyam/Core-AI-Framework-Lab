import Foundation

struct CoreAIBenchmarkStatistics: Sendable, Equatable {
    let minimum: Duration
    let median: Duration
    let mean: Duration
    let maximum: Duration
    let standardDeviation: Duration
    let runsPerSecond: Double
    let p95: Duration?

    init(trials: [CoreAIBenchmarkTrial]) throws {
        guard !trials.isEmpty else {
            throw CoreAIFunctionBenchmarkError.missingTrials
        }

        let seconds = trials.map { Self.seconds(from: $0.duration) }
        let sorted = seconds.sorted()
        let count = Double(sorted.count)
        let meanSeconds = sorted.reduce(0, +) / count
        let variance = sorted.reduce(0) { partial, value in
            let difference = value - meanSeconds
            return partial + difference * difference
        } / count
        let medianSeconds: Double
        if sorted.count.isMultiple(of: 2) {
            let upperIndex = sorted.count / 2
            medianSeconds = (sorted[upperIndex - 1] + sorted[upperIndex]) / 2
        } else {
            medianSeconds = sorted[sorted.count / 2]
        }

        minimum = .seconds(sorted[0])
        median = .seconds(medianSeconds)
        mean = .seconds(meanSeconds)
        maximum = .seconds(sorted[sorted.count - 1])
        standardDeviation = .seconds(variance.squareRoot())
        runsPerSecond = meanSeconds > 0 ? 1 / meanSeconds : 0
        if sorted.count >= 20 {
            let nearestRankIndex = Int(ceil(0.95 * count)) - 1
            p95 = .seconds(sorted[nearestRankIndex])
        } else {
            p95 = nil
        }
    }

    private static func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

extension Duration {
    var coreAIMilliseconds: Double {
        let components = components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return seconds * 1_000
    }
}
