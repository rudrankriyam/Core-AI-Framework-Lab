import SwiftUI

struct CoreAIProjectSpecializationCacheView: View {
    let link: ProjectArtifactLink
    let isInteractionDisabled: Bool
    let isUpdatingCache: Bool
    let remove: (CoreAISpecializationCacheRecord) -> Void
    let removeAll: () -> Void

    var body: some View {
        Section {
            if link.specializationCaches.isEmpty {
                Label("No Cached Configurations", systemImage: "minus.circle")
            } else {
                ForEach(link.sortedSpecializationCaches) { record in
                    CoreAISpecializationCacheRowView(
                        record: record,
                        isDisabled: isInteractionDisabled
                    ) {
                        remove(record)
                    }
                }
                Button(
                    "Remove All Cached Configurations",
                    systemImage: "trash",
                    role: .destructive,
                    action: removeAll
                )
                .disabled(isInteractionDisabled)
            }

            if isUpdatingCache {
                ProgressView("Updating Core AI cache…")
                    .accessibilityAddTraits(.updatesFrequently)
            }
        } header: {
            Label("Specialization Cache", systemImage: "cpu")
        }
    }
}
