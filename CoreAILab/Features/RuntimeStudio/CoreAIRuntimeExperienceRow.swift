import SwiftUI

struct CoreAIRuntimeExperienceRow: View {
    let mapping: CoreAIRecipeExperienceMapping

    var body: some View {
        VStack(alignment: .leading) {
            Label(
                mapping.experience.title,
                systemImage: mapping.experience.systemImage
            )
            .font(.headline)

            Text(mapping.experience.summary)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Label(capabilitySummary, systemImage: "checklist")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Label(platformSummary, systemImage: platformSystemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the local runtime experience")
    }

    private var capabilitySummary: String {
        mapping.experience.capabilities.map(\.title).joined(separator: " · ")
    }

    private var platformSummary: String {
        mapping.experience.platforms.map(\.rawValue).joined(separator: " · ")
    }

    private var platformSystemImage: String {
        mapping.experience.platforms.count > 1
            ? "desktopcomputer.and.iphone"
            : mapping.experience.platforms.first == .iOS
                ? "iphone"
                : "desktopcomputer"
    }
}
