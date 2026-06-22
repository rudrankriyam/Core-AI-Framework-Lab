import SwiftUI

struct CoreAIRecipeRewriteCatalogView: View {
    var body: some View {
        List(CoreAIRecipeRewriteCatalog.builtIn) { rewrite in
            VStack(alignment: .leading) {
                Label(rewrite.title, systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.headline)
                Text(rewrite.strategy.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(rewrite.summary)
                Text(rewrite.operatorNames.joined(separator: ", "))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Text(rewrite.evidence)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Rewrite Catalog")
    }
}
