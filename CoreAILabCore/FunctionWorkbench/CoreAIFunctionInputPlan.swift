import Foundation

struct CoreAIFunctionInputPlan: Identifiable, Sendable, Equatable {
    let name: String
    let shape: [Int]
    let generator: CoreAIFunctionInputGenerator
    let seed: UInt64

    var id: String { name }
}
