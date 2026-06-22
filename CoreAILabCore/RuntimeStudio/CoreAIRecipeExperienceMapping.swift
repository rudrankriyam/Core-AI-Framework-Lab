import Foundation

struct CoreAIRecipeExperienceMapping: Codable, Equatable, Hashable, Identifiable, Sendable {
    let recipeIdentifier: String
    let recipeRevision: String
    let experience: CoreAIExperienceDescriptor

    var id: String { experience.id }

    var runContext: CoreAIRuntimeRunContext {
        CoreAIRuntimeRunContext(
            experienceID: experience.id,
            experienceTitle: experience.title,
            recipeIdentifier: recipeIdentifier,
            recipeRevision: recipeRevision,
            recipeProvenance: .unverifiedIntent,
            comparisonIdentity: CoreAIRuntimeComparisonIdentity(
                experienceID: experience.id,
                modelIdentifier: experience.modelIdentifier,
                displayName: experience.title
            )
        )
    }
}
