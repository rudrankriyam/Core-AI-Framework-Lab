import Foundation

struct SpeakerDiarizationFeatures: Sendable, Equatable {
    let values: [Float]
    let frameCount: Int
    let binCount: Int
}
