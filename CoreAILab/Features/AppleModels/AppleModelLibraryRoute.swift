import Foundation

enum AppleModelLibraryRoute: Hashable {
    case objectDetection
    case segmentation(AppleSegmentationExample)
    case languageModel(AppleLanguageExample)
    case conversion(modelID: String)
}
