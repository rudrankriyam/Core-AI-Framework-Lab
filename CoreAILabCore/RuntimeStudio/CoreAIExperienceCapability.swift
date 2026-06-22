import Foundation

enum CoreAIExperienceCapability: String, Codable, Hashable, Sendable {
    case cancellation
    case coldWarmTiming
    case deterministicSeed
    case descriptorDrivenInputs
    case imageInput
    case negativePrompt
    case persistentRunMetadata
    case pointPrompt
    case sessionReset
    case textPrompt

    var title: String {
        switch self {
        case .cancellation:
            "Cancellation"
        case .coldWarmTiming:
            "Cold/warm timing"
        case .deterministicSeed:
            "Deterministic seed"
        case .descriptorDrivenInputs:
            "Descriptor-driven inputs"
        case .imageInput:
            "Image input"
        case .negativePrompt:
            "Negative prompt"
        case .persistentRunMetadata:
            "Project run metadata"
        case .pointPrompt:
            "Point prompt"
        case .sessionReset:
            "Session reset"
        case .textPrompt:
            "Text prompt"
        }
    }
}
