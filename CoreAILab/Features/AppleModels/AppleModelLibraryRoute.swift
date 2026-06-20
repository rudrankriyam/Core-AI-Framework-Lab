import Foundation

enum AppleModelLibraryRoute: Hashable {
    case objectDetection
    case segmentation(AppleSegmentationExample)
    case conversion(modelID: String)
}
