import Foundation

enum AppleSegmentationError: LocalizedError {
    case modelNotLoaded
    case imageNotLoaded
    case unreadableImage
    case emptyTextPrompt

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            "Import an Apple segmenter bundle before running segmentation."
        case .imageNotLoaded:
            "Choose an image before running segmentation."
        case .unreadableImage:
            "The selected image could not be decoded."
        case .emptyTextPrompt:
            "Enter an object description for SAM 3."
        }
    }
}
