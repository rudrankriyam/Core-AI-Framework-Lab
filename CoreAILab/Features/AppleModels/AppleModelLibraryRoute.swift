import Foundation

enum AppleModelLibraryRoute: Hashable {
    case objectDetection
    case segmentation(AppleSegmentationExample)
    case languageModel(AppleLanguageExample)
    case diffusion(AppleDiffusionExample)
    case conversion(modelID: String)
}
