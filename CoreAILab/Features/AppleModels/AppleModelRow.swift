import SwiftUI

struct AppleModelRow: View {
    let model: AppleCoreAIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.shortName)
                    .font(.headline)

                Spacer()

                Label(
                    model.supportedPlatforms.map(\.rawValue).joined(separator: " · "),
                    systemImage: platformSystemImage
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(model.huggingFaceID)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Label(model.runtimeSupport.title, systemImage: runtimeSystemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var runtimeSystemImage: String {
        model.isRunnableInLab ? "play.circle.fill" : "shippingbox"
    }

    private var platformSystemImage: String {
        model.supportedPlatforms.count > 1
            ? "desktopcomputer.and.iphone"
            : model.supportedPlatforms.first == .iOS ? "iphone" : "desktopcomputer"
    }
}
