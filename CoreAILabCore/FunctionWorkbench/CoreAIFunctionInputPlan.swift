import Foundation

struct CoreAIFunctionInputPlan: Sendable, Equatable {
    let name: String
    let shape: [Int]
    let generator: CoreAIFunctionInputGenerator
    let seed: UInt64
}
