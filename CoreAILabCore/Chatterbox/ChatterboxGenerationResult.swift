import Foundation

struct ChatterboxGenerationMetrics: Sendable, Equatable {
    let textPreparation: TimeInterval
    let t3Setup: TimeInterval
    let t3Prefill: TimeInterval
    let t3EmbeddingInference: TimeInterval
    let t3TransformerInference: TimeInterval
    let t3DecodeInference: TimeInterval
    let t3DecodeHost: TimeInterval
    let s3GenSetup: TimeInterval
    let s3GenNoise: TimeInterval
    let s3GenInference: TimeInterval
    let vocoderSetup: TimeInterval
    let vocoderNoise: TimeInterval
    let vocoderInference: TimeInterval
    let audioPostprocessing: TimeInterval
}

struct ChatterboxGenerationResult: Sendable, Equatable {
    let audioURL: URL
    let normalizedText: String
    let generatedTokenCount: Int
    let audioDuration: TimeInterval
    let elapsedTime: TimeInterval
    let metrics: ChatterboxGenerationMetrics

    var realTimeFactor: Double {
        elapsedTime / audioDuration
    }

    var realTimeSpeed: Double {
        audioDuration / elapsedTime
    }
}
