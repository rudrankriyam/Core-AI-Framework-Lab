import Foundation

enum AppleDiffusionError: LocalizedError {
    case pipelineNotLoaded
    case emptyPrompt
    case noImageGenerated

    var errorDescription: String? {
        switch self {
        case .pipelineNotLoaded:
            "Import an Apple diffusion resource bundle before generating."
        case .emptyPrompt:
            "Enter an image prompt before generating."
        case .noImageGenerated:
            "The diffusion pipeline completed without producing an image."
        }
    }
}
