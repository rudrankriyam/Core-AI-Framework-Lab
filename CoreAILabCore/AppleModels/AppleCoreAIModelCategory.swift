import Foundation

enum AppleCoreAIModelCategory: String, CaseIterable, Identifiable, Sendable {
    case language = "Language"
    case imageGeneration = "Image Generation"
    case vision = "Vision"
    case audio = "Audio"
    case text = "Text"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .language:
            "text.bubble"
        case .imageGeneration:
            "paintbrush"
        case .vision:
            "eye"
        case .audio:
            "waveform"
        case .text:
            "text.alignleft"
        }
    }
}
