import Foundation

struct CoreAIAssetValueSignature: Codable, Identifiable, Sendable, Equatable {
    let name: String
    let typeName: String

    var id: String { name }
}
