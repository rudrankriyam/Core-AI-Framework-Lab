import SwiftUI

struct CoreAIRuntimeExperienceSectionView: View {
    let workload: CoreAIExperienceWorkload
    let mappings: [CoreAIRecipeExperienceMapping]

    var body: some View {
        Section {
            ForEach(mappings) { mapping in
                NavigationLink(
                    value: CoreAIRuntimeExperienceRoute(
                        experienceID: mapping.experience.id
                    )
                ) {
                    CoreAIRuntimeExperienceRow(mapping: mapping)
                }
            }
        } header: {
            Label(workload.title, systemImage: workloadSystemImage)
        }
    }

    private var workloadSystemImage: String {
        switch workload {
        case .audioTranscription:
            "waveform"
        case .embedding:
            "point.3.connected.trianglepath.dotted"
        case .genericFunction:
            "function"
        case .imageGeneration:
            "photo"
        case .objectDetection:
            "viewfinder"
        case .segmentation:
            "square.3.layers.3d"
        case .textGeneration:
            "text.bubble"
        }
    }
}
