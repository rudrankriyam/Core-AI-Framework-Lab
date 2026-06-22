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

            Text(capabilitySummary)
                .font(.callout)
                .foregroundStyle(.secondary)

            Label(platformSummary, systemImage: "desktopcomputer.and.iphone")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the local runtime experience")
    }

    private var capabilitySummary: String {
        mapping.experience.capabilities.map(\.title).joined(separator: ", ")
    }

    private var platformSummary: String {
        mapping.experience.platforms.map(\.rawValue).joined(separator: " · ")
    }
}
