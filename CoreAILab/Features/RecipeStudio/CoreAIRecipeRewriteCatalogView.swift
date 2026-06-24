import SwiftUI

struct CoreAIRecipeRewriteCatalogView: View {
    var body: some View {
        List(CoreAIRecipeRewriteCatalog.builtIn) { rewrite in
            HStack(alignment: .firstTextBaseline) {
                Label(rewrite.title, systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.headline)

                Spacer()

                Text(rewrite.strategy.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .help(
                "\(rewrite.summary) Operators: \(rewrite.operatorNames.joined(separator: ", ")). \(rewrite.evidence)"
            )
        }
        .navigationTitle("Rewrite Catalog")
    }
}
