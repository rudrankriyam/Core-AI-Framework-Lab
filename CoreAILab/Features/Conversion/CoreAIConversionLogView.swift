#if os(macOS)
import SwiftUI

struct CoreAIConversionLogView: View {
    let entries: [CoreAIConversionLogEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if entries.isEmpty {
                        Label(
                            "Converter output will appear here",
                            systemImage: "text.alignleft"
                        )
                        .foregroundStyle(.secondary)
                        .padding()
                    } else {
                        ForEach(entries) { entry in
                            Text(entry.message)
                                .font(.callout.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                }
                .padding()
                .textSelection(.enabled)
            }
            .background(.black.opacity(0.04))
            .onChange(of: entries.count) {
                guard let lastID = entries.last?.id else { return }
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
        .accessibilityLabel("Conversion log")
    }
}
#endif
