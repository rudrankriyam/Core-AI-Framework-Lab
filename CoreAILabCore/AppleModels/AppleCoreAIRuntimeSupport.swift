import Foundation

enum AppleCoreAIRuntimeSupport: String, Hashable, Sendable {
    case genericAsset
    case languageModel
    case diffusion
    case audio
    case segmentation
    case objectDetection

    var title: String {
        switch self {
        case .genericAsset:
            "Generic Core AI asset"
        case .languageModel:
            "Apple language-model runtime"
        case .diffusion:
            "Apple diffusion runtime"
        case .audio:
            "Core AI audio runtime"
        case .segmentation:
            "Apple segmentation runtime"
        case .objectDetection:
            "Apple object-detection runtime"
        }
    }

    var productName: String? {
        switch self {
        case .genericAsset:
            nil
        case .languageModel:
            "CoreAILM"
        case .diffusion:
            "CoreAIDiffusion"
        case .audio:
            nil
        case .segmentation:
            "CoreAISegmentation"
        case .objectDetection:
            "CoreAIObjectDetection"
        }
    }

    var detail: String {
        switch self {
        case .genericAsset:
            "Import the exported .aimodel into the Asset Inspector, then build a task adapter from its function contract."
        case .languageModel:
            "Apple's CoreAILM package provides tokenization, generation, sampling, state, and profiling utilities."
        case .diffusion:
            "Apple's CoreAIDiffusion package orchestrates the multi-asset diffusion pipeline and schedulers."
        case .audio:
            "Core AI Lab decodes audio, runs Apple's exported Wav2Vec2 function, and performs greedy CTC transcription."
        case .segmentation:
            "Apple's CoreAISegmentation package provides image preparation, prompts, post-processing, and visualization."
        case .objectDetection:
            "Apple's CoreAIObjectDetection package loads YOLOS exports and performs preprocessing and COCO post-processing."
        }
    }
}
