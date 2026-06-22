import Foundation

struct CoreAIRuntimeRunContext: Equatable, Hashable, Sendable {
    let experienceID: String
    let experienceTitle: String
    let recipeIdentifier: String
    let recipeRevision: String
    let recipeProvenance: CoreAIRuntimeRecipeProvenance
    let comparisonIdentity: CoreAIRuntimeComparisonIdentity

    static func workspaceDefault(
        experienceID: String,
        title: String,
        modelIdentifier: String
    ) -> CoreAIRuntimeRunContext {
        CoreAIRuntimeRunContext(
            experienceID: experienceID,
            experienceTitle: title,
            recipeIdentifier: "workspace.\(modelIdentifier)",
            recipeRevision: "unversioned-workspace",
            recipeProvenance: .unattributed,
            comparisonIdentity: CoreAIRuntimeComparisonIdentity(
                experienceID: experienceID,
                modelIdentifier: modelIdentifier,
                displayName: title
            )
        )
    }
}
