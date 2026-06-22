import Foundation

struct CoreAIAssetOperationCount: Codable, Equatable, Identifiable, Sendable {
    let operationName: String
    let count: Int

    var id: String { operationName }
}
