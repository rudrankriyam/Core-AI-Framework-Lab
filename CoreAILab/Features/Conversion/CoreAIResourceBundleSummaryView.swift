import SwiftUI

#if os(macOS)
struct CoreAIResourceBundleSummaryView: View {
    let artifact: CoreAIConversionArtifact

    var body: some View {
        Form {
            Section("Core AI Resource Bundle") {
                LabeledContent("Name", value: artifact.name)
                LabeledContent("Kind", value: artifact.resourceKind ?? "unknown")
                LabeledContent("Location") {
                    Text(artifact.url.path)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }

            ContentUnavailableView(
                "Runtime Adapter Required",
                systemImage: "shippingbox",
                description: Text(
                    "This multi-asset bundle was preserved as one runnable unit. Open its matching Apple Models playground when that runtime adapter is available."
                )
            )
        }
        .formStyle(.grouped)
        .navigationTitle(artifact.name)
    }
}
#endif
