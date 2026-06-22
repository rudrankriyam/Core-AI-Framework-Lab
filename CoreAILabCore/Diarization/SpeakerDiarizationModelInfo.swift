import Foundation

struct SpeakerDiarizationModelInfo: Sendable, Equatable {
    let assetName: String
    let frameCount: Int
    let featureBinCount: Int
    let embeddingDimension: Int
    let scalarTypeName: String
}
