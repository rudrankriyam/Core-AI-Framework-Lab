#if os(macOS)
import SwiftUI

struct CoreAIConversionLogView: View {
    let entries: [CoreAIConversionLogEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if entries.isEmpty {
                        ContentUnavailableView(
                            "No Converter Output",
                            systemImage: "text.alignleft",
                            description: Text(
                                "Start a conversion to stream the original process output here."
                            )
                        )
                        .frame(maxWidth: .infinity, minHeight: 200)
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
            .background(.secondary.opacity(0.08))
            .onChange(of: entries.count) {
                guard let lastID = entries.last?.id else { return }
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
        .accessibilityLabel("Conversion log")
    }
}
#endif
