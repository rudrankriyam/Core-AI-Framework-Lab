import SwiftUI

struct AppleModelCatalogSourceView: View {
    let modelCount: Int
    let sourceRevision: String
    let sourceRepositoryURL: URL?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Apple Core AI Models", systemImage: "apple.logo")
                .font(.headline)

            Spacer()

            Label("\(modelCount) recipes", systemImage: "list.bullet")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let sourceRepositoryURL {
                Link(destination: sourceRepositoryURL) {
                    Label {
                        Text(sourceRevision.prefix(8))
                            .monospaced()
                    } icon: {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .help("Pinned Apple model recipes; model weights are not bundled")
    }
}
