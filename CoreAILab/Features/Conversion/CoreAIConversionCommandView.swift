#if os(macOS)
import SwiftUI

struct CoreAIConversionCommandView: View {
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Reproducible command", systemImage: "terminal")
                .font(.headline)

            ScrollView(.horizontal) {
                Text(command)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }
            .scrollIndicators(.visible)

            Text("Displayed for evidence only. Core AI Lab passes these arguments directly without invoking a shell.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
