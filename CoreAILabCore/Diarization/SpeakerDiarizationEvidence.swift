import Foundation

struct SpeakerDiarizationEvidence: Sendable, Equatable {
    let modelName: String
    let speechRegionCount: Int
    let analysisWindowCount: Int
    let decodeSeconds: Double
    let segmentationSeconds: Double
    let featureExtractionSeconds: Double
    let inferenceSeconds: Double
    let totalSeconds: Double
    let clusteringThreshold: Float
}
