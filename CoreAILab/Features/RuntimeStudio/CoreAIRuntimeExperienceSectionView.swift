import SwiftUI

struct CoreAIRuntimeExperienceSectionView: View {
    let workload: CoreAIExperienceWorkload
    let mappings: [CoreAIRecipeExperienceMapping]

    var body: some View {
        Section(workload.title) {
            ForEach(mappings) { mapping in
                NavigationLink(
                    value: CoreAIRuntimeExperienceRoute(
                        experienceID: mapping.experience.id
                    )
                ) {
                    CoreAIRuntimeExperienceRow(mapping: mapping)
                }
            }
        }
    }
}
