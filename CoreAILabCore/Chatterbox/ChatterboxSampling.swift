import Foundation

final class ChatterboxRandomGenerator: @unchecked Sendable, RandomNumberGenerator {
    private var state: UInt64
    private var spareNormal: Double?

    init(seed: UInt64) {
        state = seed
    }

    func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    func nextUnitDouble() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    func nextNormal() -> Double {
        if let spareNormal {
            self.spareNormal = nil
            return spareNormal
        }

        let first = max(nextUnitDouble(), Double.leastNonzeroMagnitude)
        let second = nextUnitDouble()
        let magnitude = sqrt(-2 * log(first))
        let angle = 2 * Double.pi * second
        spareNormal = magnitude * sin(angle)
        return magnitude * cos(angle)
    }
}

enum ChatterboxSampler {
    static func sample(
        logits: [Float],
        generatedTokens: [Int],
        random: ChatterboxRandomGenerator,
        temperature: Float = 0.8,
        topK: Int = 1_000,
        topP: Double = 0.95,
        repetitionPenalty: Float = 1.2
    ) throws -> Int {
        guard !logits.isEmpty else {
            throw ChatterboxCoreAIError.invalidOutputShape("The T3 logits were empty.")
        }

        let safeTemperature = max(temperature, 0.0001)
        var adjusted = logits.map { value in
            value.isFinite ? value / safeTemperature : -.infinity
        }

        for token in Set(generatedTokens) where adjusted.indices.contains(token) {
            if adjusted[token] < 0 {
                adjusted[token] *= repetitionPenalty
            } else {
                adjusted[token] /= repetitionPenalty
            }
        }

        let candidateCount = min(max(topK, 1), adjusted.count)
        let sortedIndices = adjusted.indices
            .sorted { adjusted[$0] > adjusted[$1] }
            .prefix(candidateCount)
        guard let maximum = sortedIndices.first.map({ adjusted[$0] }), maximum.isFinite else {
            throw ChatterboxCoreAIError.invalidOutputShape("The T3 logits were not finite.")
        }

        var candidates = [(token: Int, weight: Double)]()
        candidates.reserveCapacity(candidateCount)
        for token in sortedIndices {
            candidates.append(
                (token, exp(Double(adjusted[token] - maximum)))
            )
        }

        let totalWeight = candidates.reduce(0) { $0 + $1.weight }
        let nucleusTarget = totalWeight * min(max(topP, 0), 1)
        var nucleus = [(token: Int, weight: Double)]()
        nucleus.reserveCapacity(candidates.count)
        var cumulativeWeight = 0.0
        for candidate in candidates {
            nucleus.append(candidate)
            cumulativeWeight += candidate.weight
            if cumulativeWeight >= nucleusTarget {
                break
            }
        }

        let draw = random.nextUnitDouble() * cumulativeWeight
        var runningWeight = 0.0
        for candidate in nucleus {
            runningWeight += candidate.weight
            if draw <= runningWeight {
                return candidate.token
            }
        }
        return nucleus.last?.token ?? candidates[0].token
    }
}
