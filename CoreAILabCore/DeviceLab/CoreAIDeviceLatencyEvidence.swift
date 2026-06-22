import Foundation

struct CoreAIDeviceLatencyEvidence: Codable, Equatable, Sendable {
    static let maximumSampleCount = 10_000

    let availability: CoreAIDeviceMetricAvailability
    let samplesMilliseconds: [Double]
    let minimumMilliseconds: Double?
    let medianMilliseconds: Double?
    let meanMilliseconds: Double?
    let p95Milliseconds: Double?
    let maximumMilliseconds: Double?

    static var unavailable: Self {
        Self(
            availability: .unavailable,
            samplesMilliseconds: [],
            minimumMilliseconds: nil,
            medianMilliseconds: nil,
            meanMilliseconds: nil,
            p95Milliseconds: nil,
            maximumMilliseconds: nil
        )
    }

    init(observedSamples samples: [Double]) throws {
        guard !samples.isEmpty, samples.count <= Self.maximumSampleCount else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "latency.samplesMilliseconds",
                reason: "an observed distribution needs 1 through \(Self.maximumSampleCount) samples"
            )
        }
        guard samples.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "latency.samplesMilliseconds",
                reason: "samples must be finite and zero or greater"
            )
        }
        guard samples.reduce(0, +).isFinite else {
            throw CoreAIDeviceEvidenceError.arithmeticOverflow(
                path: "latency.samplesMilliseconds"
            )
        }
        let distribution = Self.distribution(for: samples)
        availability = .observed
        samplesMilliseconds = samples
        minimumMilliseconds = distribution.minimum
        medianMilliseconds = distribution.median
        meanMilliseconds = distribution.mean
        p95Milliseconds = distribution.p95
        maximumMilliseconds = distribution.maximum
    }

    init(
        availability: CoreAIDeviceMetricAvailability,
        samplesMilliseconds: [Double],
        minimumMilliseconds: Double?,
        medianMilliseconds: Double?,
        meanMilliseconds: Double?,
        p95Milliseconds: Double?,
        maximumMilliseconds: Double?
    ) {
        self.availability = availability
        self.samplesMilliseconds = samplesMilliseconds
        self.minimumMilliseconds = minimumMilliseconds
        self.medianMilliseconds = medianMilliseconds
        self.meanMilliseconds = meanMilliseconds
        self.p95Milliseconds = p95Milliseconds
        self.maximumMilliseconds = maximumMilliseconds
    }

    func validate(path: String = "latency") throws {
        switch availability {
        case .unavailable:
            guard samplesMilliseconds.isEmpty,
                  minimumMilliseconds == nil,
                  medianMilliseconds == nil,
                  meanMilliseconds == nil,
                  p95Milliseconds == nil,
                  maximumMilliseconds == nil else {
                throw CoreAIDeviceEvidenceError.invalidValue(
                    path: path,
                    reason: "unavailable latency evidence must not contain measurements"
                )
            }
        case .observed:
            let expected = try Self(observedSamples: samplesMilliseconds)
            guard approximatelyEqual(minimumMilliseconds, expected.minimumMilliseconds),
                  approximatelyEqual(medianMilliseconds, expected.medianMilliseconds),
                  approximatelyEqual(meanMilliseconds, expected.meanMilliseconds),
                  approximatelyEqual(p95Milliseconds, expected.p95Milliseconds),
                  approximatelyEqual(maximumMilliseconds, expected.maximumMilliseconds) else {
                throw CoreAIDeviceEvidenceError.invalidValue(
                    path: path,
                    reason: "distribution values do not match the measured samples"
                )
            }
        }
    }

    private static func distribution(
        for samples: [Double]
    ) -> (minimum: Double, median: Double, mean: Double, p95: Double, maximum: Double) {
        let sorted = samples.sorted()
        let count = sorted.count
        let median: Double
        if count.isMultiple(of: 2) {
            median = (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        } else {
            median = sorted[count / 2]
        }
        let p95Index = Int(ceil(Double(count) * 0.95)) - 1
        return (
            sorted[0],
            median,
            sorted.reduce(0, +) / Double(count),
            sorted[p95Index],
            sorted[count - 1]
        )
    }

    private func approximatelyEqual(_ lhs: Double?, _ rhs: Double?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        let scale = max(1, max(abs(lhs), abs(rhs)))
        return abs(lhs - rhs) <= scale * 1e-12
    }
}
