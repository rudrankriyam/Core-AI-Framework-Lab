import Foundation

enum AppleCoreAIModelCatalogError: LocalizedError {
    case missingResource

    var errorDescription: String? {
        switch self {
        case .missingResource:
            "The bundled Apple Core AI model catalog could not be found."
        }
    }
}
