#if os(macOS)
import SwiftUI

struct CoreAIConversionOutputsView: View {
    let artifacts: [CoreAIConversionArtifact]
    let logURL: URL?
    let revealInFinder: (CoreAIConversionArtifact) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Outputs", systemImage: "shippingbox.fill")
                .font(.headline)

            ForEach(artifacts) { artifact in
                HStack {
                    NavigationLink(value: artifact) {
                        Label(artifact.name, systemImage: artifact.systemImage)
                    }

                    Spacer()

                    Button(
                        "Reveal \(artifact.name) in Finder",
                        systemImage: "folder",
                        action: { revealInFinder(artifact) }
                    )
                    .labelStyle(.iconOnly)
                    .help("Reveal in Finder")
                }
            }

            if let logURL {
                LabeledContent("Evidence log") {
                    Text(logURL.lastPathComponent)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }
}
#endif
