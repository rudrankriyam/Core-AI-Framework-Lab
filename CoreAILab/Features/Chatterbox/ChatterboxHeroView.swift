import SwiftUI

struct ChatterboxHeroView: View {
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Chatterbox Turbo", systemImage: "waveform.circle.fill")
                    .font(.title2.bold())

                Text("Expressive text-to-speech running through Apple Core AI. No MLX runtime.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Label("Core AI · Apple GPU · 24 kHz audio", systemImage: "laptopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }
}
