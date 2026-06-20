import CoreGraphics
import Foundation

struct AppleObjectDetection: Identifiable, Sendable {
    let id: Int
    let boundingBox: CGRect
    let label: String
    let confidence: Float
}
