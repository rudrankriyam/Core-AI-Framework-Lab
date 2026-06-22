import Foundation

enum CoreAIExperienceAdapter: String, Codable, Hashable, Sendable {
    case appleAudioTranscription
    case appleDiffusion
    case appleLanguage
    case appleObjectDetection
    case appleSegmentation
    case genericFunctionWorkbench

    func supports(_ workload: CoreAIExperienceWorkload) -> Bool {
        switch self {
        case .appleAudioTranscription:
            workload == .audioTranscription
        case .appleDiffusion:
            workload == .imageGeneration
        case .appleLanguage:
            workload == .textGeneration
        case .appleObjectDetection:
            workload == .objectDetection
        case .appleSegmentation:
            workload == .segmentation
        case .genericFunctionWorkbench:
            workload == .genericFunction
        }
    }
}
