import Foundation

enum AppleObjectDetectionError: LocalizedError {
    case modelNotLoaded
    case imageNotLoaded
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            "Import an exported YOLOS .aimodel before running detection."
        case .imageNotLoaded:
            "Choose an image before running detection."
        case .unreadableImage:
            "The selected file could not be decoded as an image."
        }
    }
}
