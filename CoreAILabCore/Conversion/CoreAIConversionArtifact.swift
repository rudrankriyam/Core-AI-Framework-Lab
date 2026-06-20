import Foundation

struct CoreAIConversionArtifact: Hashable, Identifiable, Sendable {
    let url: URL
    let kind: CoreAIConversionArtifactKind
    let resourceKind: String?

    init(
        url: URL,
        kind: CoreAIConversionArtifactKind = .modelAsset,
        resourceKind: String? = nil
    ) {
        self.url = url
        self.kind = kind
        self.resourceKind = resourceKind
    }

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    var systemImage: String {
        switch kind {
        case .modelAsset:
            "cube.transparent"
        case .resourceBundle:
            "shippingbox.fill"
        }
    }
}
