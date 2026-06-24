import SwiftUI

struct AppleModelRow: View {
    let model: AppleCoreAIModel

    var body: some View {
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
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .help("\(model.huggingFaceID) · \(model.runtimeSupport.title)")
    }

    private var platformSystemImage: String {
        model.supportedPlatforms.count > 1
            ? "desktopcomputer.and.iphone"
            : model.supportedPlatforms.first == .iOS ? "iphone" : "desktopcomputer"
    }
}
