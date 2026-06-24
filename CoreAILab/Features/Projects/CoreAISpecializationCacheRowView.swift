import SwiftUI

struct CoreAISpecializationCacheRowView: View {
    let record: CoreAISpecializationCacheRecord
    let isDisabled: Bool
    let remove: () -> Void

    var body: some View {
        HStack {
            Label(record.configurationTitle, systemImage: "cpu")

            Spacer()

            Text(
                record.lastUsedAt,
                format: .relative(presentation: .named)
            )
                .foregroundStyle(.secondary)

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
        .help(
            record.wasLoadedFromCache
                ? "Loaded from an existing specialization cache"
                : "Created by specialization"
        )
    }
}
