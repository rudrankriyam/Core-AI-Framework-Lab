import Foundation

enum AppleLanguageModelError: LocalizedError {
    case modelNotLoaded
    case emptyPrompt

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            "Import an Apple language-model resource bundle before generating."
        case .emptyPrompt:
            "Enter a prompt before generating a response."
        }
    }
}
