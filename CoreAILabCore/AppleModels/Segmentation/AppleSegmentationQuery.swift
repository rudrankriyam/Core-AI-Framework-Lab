import Foundation

enum AppleSegmentationQuery: Equatable, Sendable {
    case point(x: Float, y: Float)
    case text(String)
}
