import SwiftUI

struct CoreAIRuntimeUnsupportedExperienceView: View {
    let mapping: CoreAIRecipeExperienceMapping

    var body: some View {
        ContentUnavailableView(
            "Adapter Not Available in This Build",
            systemImage: "exclamationmark.triangle",
            description: Text(
                "The recipe maps \(mapping.experience.modelIdentifier) to \(mapping.experience.adapter.rawValue), but this build cannot resolve that model preset."
            )
        )
        .navigationTitle(mapping.experience.title)
    }
}
