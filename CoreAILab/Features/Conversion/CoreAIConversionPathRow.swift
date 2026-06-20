#if os(macOS)
import SwiftUI

struct CoreAIConversionPathRow: View {
    let title: String
    let url: URL?
    let fallback: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 6) {
                Text(url?.path ?? fallback)
                    .foregroundStyle(url == nil ? .secondary : .primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
    }
}
#endif
