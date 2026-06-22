import Foundation

enum CoreAIRuntimeRecipeProvenance: String, Codable, Equatable, Hashable, Sendable {
    case unattributed
    case unverifiedIntent = "unverified_intent"

    var requiresArtifactFamilyValidation: Bool {
        self != .unattributed
    }
}
