import Foundation

enum CoreAIArtifactKind: String, CaseIterable, Codable, Sendable {
    case modelAsset
    case resourceBundle
    case auxiliaryFile

    var title: String {
        switch self {
        case .modelAsset:
            "Core AI model"
        case .resourceBundle:
            "Resource bundle"
        case .auxiliaryFile:
            "Supporting file"
        }
    }

    var systemImage: String {
        switch self {
        case .modelAsset:
            "cube.transparent"
        case .resourceBundle:
            "shippingbox.fill"
        case .auxiliaryFile:
            "doc"
        }
    }

    static func infer(from url: URL, isDirectory: Bool) -> Self {
        let pathExtension = url.pathExtension.lowercased()
        if pathExtension == "aimodel" || pathExtension == "aimodelc" {
            return .modelAsset
        }
        return isDirectory ? .resourceBundle : .auxiliaryFile
    }
}
