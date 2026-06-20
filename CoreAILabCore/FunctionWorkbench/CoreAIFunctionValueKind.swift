import Foundation

enum CoreAIFunctionValueKind: Sendable, Equatable {
    case tensor(CoreAITensorContract)
    case image(CoreAIImageContract)
    case unknown

    var summary: String {
        switch self {
        case .tensor(let tensor):
            "\(tensor.scalarTypeName) \(tensor.shape)"
        case .image(let image):
            "image \(image.width)×\(image.height), pixel format \(image.pixelFormatType)"
        case .unknown:
            "Unknown value type"
        }
    }
}
