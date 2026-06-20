import Foundation

struct CoreAIConversionArtifact: Hashable, Identifiable, Sendable {
    let url: URL

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}
