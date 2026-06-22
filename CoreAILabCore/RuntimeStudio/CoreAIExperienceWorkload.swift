import Foundation

enum CoreAIExperienceWorkload: String, Codable, CaseIterable, Hashable, Sendable {
    case audioTranscription
    case embedding
    case genericFunction
    case imageGeneration
    case objectDetection
    case segmentation
    case textGeneration

    var title: String {
        switch self {
        case .audioTranscription:
            "Audio"
        case .embedding:
            "Embeddings"
        case .genericFunction:
            "Generic Functions"
        case .imageGeneration:
            "Image Generation"
        case .objectDetection:
            "Object Detection"
        case .segmentation:
            "Segmentation"
        case .textGeneration:
            "Language"
        }
    }

    var sortOrder: Int {
        switch self {
        case .textGeneration:
            0
        case .embedding:
            1
        case .objectDetection:
            2
        case .segmentation:
            3
        case .audioTranscription:
            4
        case .imageGeneration:
            5
        case .genericFunction:
            6
        }
    }
}
