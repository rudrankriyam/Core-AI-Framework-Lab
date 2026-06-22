import Foundation

struct CoreAIAssetStorageTypeSummary: Codable, Equatable, Identifiable, Sendable {
    let typeName: String
    let count: Int

    var id: String { typeName }
}
