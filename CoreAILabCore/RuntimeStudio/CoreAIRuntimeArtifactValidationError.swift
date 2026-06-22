import Foundation

enum CoreAIRuntimeArtifactValidationError: LocalizedError, Equatable {
    case familyCouldNotBeVerified(expectedModelIdentifier: String)
    case modelFamilyMismatch(
        expectedModelIdentifier: String,
        detectedModelIdentifier: String
    )

    var errorDescription: String? {
        switch self {
        case .familyCouldNotBeVerified(let expectedModelIdentifier):
            "The imported artifact does not identify itself as \(expectedModelIdentifier). Choose the export produced for this Runtime Studio experience."
        case .modelFamilyMismatch(
            let expectedModelIdentifier,
            let detectedModelIdentifier
        ):
            "This experience expects \(expectedModelIdentifier), but the imported artifact identifies as \(detectedModelIdentifier)."
        }
    }
}
