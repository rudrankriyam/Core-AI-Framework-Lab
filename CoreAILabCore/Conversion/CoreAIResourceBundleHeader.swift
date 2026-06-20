import Foundation

struct CoreAIResourceBundleHeader: Decodable, Equatable, Sendable {
    let metadataVersion: String
    let kind: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case metadataVersion = "metadata_version"
        case kind
        case name
    }
}
