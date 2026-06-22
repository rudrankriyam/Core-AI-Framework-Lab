import Foundation

struct SpeakerDiarizationClusterAssignment: Sendable, Equatable {
    let speakerIndex: Int
    let similarity: Float?
}

struct SpeakerDiarizationSpeakerClusterer: Sendable {
    let similarityThreshold: Float

    private struct Cluster: Sendable {
        var centroid: [Float]
        var observationCount: Int
    }

    private var clusters: [Cluster] = []

    init(similarityThreshold: Float = 0.65) {
        self.similarityThreshold = similarityThreshold
    }

    var clusterCount: Int {
        clusters.count
    }

    mutating func assign(
        embedding: [Float]
    ) throws -> SpeakerDiarizationClusterAssignment {
        let normalized = try Self.normalized(embedding)
        let similarities = try clusters.map { cluster in
            try Self.cosine(normalized, cluster.centroid)
        }
        if let best = similarities.enumerated().max(by: { $0.element < $1.element }),
           best.element >= similarityThreshold {
            try updateCluster(at: best.offset, with: normalized)
            return SpeakerDiarizationClusterAssignment(
                speakerIndex: best.offset,
                similarity: best.element
            )
        }

        clusters.append(Cluster(centroid: normalized, observationCount: 1))
        return SpeakerDiarizationClusterAssignment(
            speakerIndex: clusters.count - 1,
            similarity: nil
        )
    }

    private mutating func updateCluster(at index: Int, with embedding: [Float]) throws {
        let count = Float(clusters[index].observationCount)
        for dimension in embedding.indices {
            clusters[index].centroid[dimension] = (
                (clusters[index].centroid[dimension] * count) + embedding[dimension]
            ) / (count + 1)
        }
        clusters[index].centroid = try Self.normalized(clusters[index].centroid)
        clusters[index].observationCount += 1
    }

    private static func cosine(_ left: [Float], _ right: [Float]) throws -> Float {
        guard left.count == right.count, !left.isEmpty else {
            throw SpeakerDiarizationError.invalidEmbedding(
                "embedding dimensions do not match"
            )
        }
        var result = Float.zero
        for index in left.indices {
            result += left[index] * right[index]
        }
        return result
    }

    private static func normalized(_ values: [Float]) throws -> [Float] {
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else {
            throw SpeakerDiarizationError.invalidEmbedding(
                "embedding is empty or non-finite"
            )
        }
        var sumOfSquares = Float.zero
        for value in values {
            sumOfSquares += value * value
        }
        let norm = sqrt(sumOfSquares)
        guard norm > 1e-6 else {
            throw SpeakerDiarizationError.invalidEmbedding(
                "embedding norm is zero"
            )
        }
        return values.map { $0 / norm }
    }
}
