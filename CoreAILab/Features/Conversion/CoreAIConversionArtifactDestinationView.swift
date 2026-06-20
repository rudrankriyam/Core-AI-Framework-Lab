import SwiftUI

#if os(macOS)
struct CoreAIConversionArtifactDestinationView: View {
    let artifact: CoreAIConversionArtifact

    var body: some View {
        switch artifact.kind {
        case .modelAsset:
            CoreAIAssetInspectorView(initialURL: artifact.url)
        case .resourceBundle:
            if artifact.resourceKind == "segmenter",
               let example = AppleSegmentationExample(resourceBundleURL: artifact.url) {
                AppleSegmentationWorkspaceView(
                    example: example,
                    initialModelURL: artifact.url
                )
            } else if artifact.resourceKind == "llm",
                      let example = AppleLanguageExample(resourceBundleURL: artifact.url) {
                AppleLanguageWorkspaceView(
                    example: example,
                    initialModelURL: artifact.url
                )
            } else {
                CoreAIResourceBundleSummaryView(artifact: artifact)
            }
        }
    }
}
#endif
