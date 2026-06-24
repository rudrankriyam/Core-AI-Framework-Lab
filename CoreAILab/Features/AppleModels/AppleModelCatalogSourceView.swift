import SwiftUI

struct AppleModelCatalogSourceView: View {
    let modelCount: Int
    let sourceRevision: String
    let sourceRepositoryURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Apple Core AI Models", systemImage: "apple.logo")
                .font(.headline)

            Text("A pinned snapshot of Apple's model registry. Entries are export recipes, not bundled weights.")
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("\(modelCount) recipes", systemImage: "list.bullet")
                    Label {
                        Text(sourceRevision.prefix(8))
                            .monospaced()
                    } icon: {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                }

                VStack(alignment: .leading) {
                    Label("\(modelCount) recipes", systemImage: "list.bullet")
                    Label {
                        Text(sourceRevision.prefix(8))
                            .monospaced()
                    } icon: {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if let sourceRepositoryURL {
                Link("Open apple/coreai-models", destination: sourceRepositoryURL)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}
