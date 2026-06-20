import SwiftUI

struct AppleModelRow: View {
    let model: AppleCoreAIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.shortName)
                    .font(.headline)

                Spacer()

                Text(model.supportedPlatforms.map(\.rawValue).joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(model.huggingFaceID)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)

            Label(model.runtimeSupport.title, systemImage: runtimeSystemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var runtimeSystemImage: String {
        model.isRunnableInLab ? "play.circle.fill" : "shippingbox"
    }
}
