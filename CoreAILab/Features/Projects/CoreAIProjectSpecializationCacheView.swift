import SwiftUI

struct CoreAIProjectSpecializationCacheView: View {
    let link: ProjectArtifactLink
    let isInteractionDisabled: Bool
    let isUpdatingCache: Bool
    let remove: (CoreAISpecializationCacheRecord) -> Void
    let removeAll: () -> Void

    var body: some View {
        Section("Specialization Cache") {
            if link.specializationCaches.isEmpty {
                Text("Specialize this project artifact to register a cache entry.")
                    .foregroundStyle(.secondary)
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
                Label("Updating Core AI cache…", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
