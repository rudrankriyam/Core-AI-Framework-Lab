import Foundation

enum CoreAIConversionError: LocalizedError {
    case alreadyRunning
    case incompleteConfiguration
    case noArtifactsFound
    case processFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "A conversion is already running."
        case .incompleteConfiguration:
            "Choose a recipe repository, output folder, and working uv executable first."
        case .noArtifactsFound:
            "The converter exited successfully, but it did not create or update a Core AI artifact in the output folder."
        case .processFailed(let exitCode):
            "The converter exited with status \(exitCode). Read the evidence log for the original error."
        }
    }
}
