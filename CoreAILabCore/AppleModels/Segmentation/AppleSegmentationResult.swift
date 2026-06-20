import CoreGraphics
import Foundation

struct AppleSegmentationResult: Sendable {
    let renderedImage: CGImage
    let segmentCount: Int
    let scores: [Float]
}
