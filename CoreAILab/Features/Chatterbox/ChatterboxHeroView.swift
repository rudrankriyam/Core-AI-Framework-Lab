import SwiftUI

struct ChatterboxHeroView: View {
    let manifest: CoreAIRecipeManifest?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    manifest?.displayName ?? "Bundled Text to Speech",
                    systemImage: manifest?.systemImage ?? "waveform.circle"
                )
                    .font(.title2.bold())

                Text(
                    manifest?.summary
                        ?? "Loading the bundled Core AI recipe and its validated runtime contract."
                )
                    .font(.body)
                    .foregroundStyle(.secondary)

                Label(targetDescription, systemImage: "laptopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private var targetDescription: String {
        guard let target = manifest?.defaultTarget else {
            return "Core AI · Resolving target"
        }
        return "Core AI · \(target.displayName) · \(target.platform.rawValue) \(target.minimumOSVersion)+"
    }
}
