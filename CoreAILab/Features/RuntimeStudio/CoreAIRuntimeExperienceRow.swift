import SwiftUI

struct CoreAIRuntimeExperienceRow: View {
    let mapping: CoreAIRecipeExperienceMapping

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(
                mapping.experience.title,
                systemImage: mapping.experience.systemImage
            )
            .font(.headline)

            Spacer()

            Label(platformSummary, systemImage: platformSystemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the local runtime experience")
        .help("\(mapping.experience.summary) \(capabilitySummary)")
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
