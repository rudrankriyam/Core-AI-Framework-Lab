#if os(macOS)
import SwiftUI

struct CoreAIConversionEnvironmentCheckView: View {
    let check: CoreAIConversionEnvironmentCheck

    var body: some View {
        LabeledContent {
            Text(statusTitle)
                .foregroundStyle(statusStyle)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.title)
                    Text(check.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(statusStyle)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(check.title), \(statusTitle), \(check.detail)")
    }

    private var statusTitle: String {
        switch check.status {
        case .passed:
            "Ready"
        case .warning:
            "Review"
        case .failed:
            "Required"
        }
    }

    private var systemImage: String {
        switch check.status {
        case .passed:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .failed:
            "xmark.circle.fill"
        }
    }

    private var statusStyle: AnyShapeStyle {
        switch check.status {
        case .passed:
            AnyShapeStyle(.green)
        case .warning:
            AnyShapeStyle(.orange)
        case .failed:
            AnyShapeStyle(.red)
        }
    }
}
#endif
