import Foundation

struct CoreAIFunctionValueContract: Identifiable, Sendable, Equatable {
    let name: String
    let kind: CoreAIFunctionValueKind

    var id: String { name }
}
