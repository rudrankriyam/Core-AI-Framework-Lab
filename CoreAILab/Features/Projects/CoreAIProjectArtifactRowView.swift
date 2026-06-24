import SwiftUI

struct CoreAIProjectArtifactRowView: View {
    let link: ProjectArtifactLink

    var body: some View {
        HStack {
            Label(
                link.displayName,
                systemImage: link.artifact?.kind?.systemImage ?? "shippingbox"
            )

            Spacer()

            if let artifact = link.artifact {
                HStack {
                    Text(artifact.byteCount, format: .byteCount(style: .file))
                    Text(artifact.shortDigest)
                        .monospaced()
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
