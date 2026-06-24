import Foundation

enum CoreAIExperienceAdapter: String, Codable, Hashable, Sendable {
    case appleAudioTranscription
    case appleDiffusion
    case appleLanguage
    case appleObjectDetection
    case appleSegmentation
    case genericFunctionWorkbench

    var title: String {
        switch self {
        case .appleAudioTranscription:
            "Apple Audio Transcription"
        case .appleDiffusion:
            "Apple Diffusion"
        case .appleLanguage:
            "Apple Language"
        case .appleObjectDetection:
            "Apple Object Detection"
        case .appleSegmentation:
            "Apple Segmentation"
        case .genericFunctionWorkbench:
            "Function Workbench"
        }
    }

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
