import Foundation

struct CoreAIAssetValueSignature: Identifiable, Sendable, Equatable {
    let name: String
    let typeName: String

    var id: String { name }
}
