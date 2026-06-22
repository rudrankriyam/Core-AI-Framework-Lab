import SwiftUI

struct CoreAISpecializationCacheRowView: View {
    let record: CoreAISpecializationCacheRecord
    let isDisabled: Bool
    let remove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Label(record.configurationTitle, systemImage: "cpu")
                Text(
                    record.lastUsedAt,
                    format: .relative(presentation: .named)
                )
                .foregroundStyle(.secondary)
                Text(
                    record.wasLoadedFromCache
                        ? "Loaded from existing cache"
                        : "Created by specialization"
                )
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(
                "Remove \(record.configurationTitle)",
                systemImage: "trash",
                role: .destructive,
                action: remove
            )
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(isDisabled)
        }
        .accessibilityElement(children: .contain)
    }
}
