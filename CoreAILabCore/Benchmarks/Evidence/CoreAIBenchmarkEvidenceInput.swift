import Foundation

struct CoreAIBenchmarkEvidenceInput: Codable, Sendable, Equatable {
    let name: String
    let shape: [Int]
    let generator: String
    let seed: UInt64

    init(plan: CoreAIFunctionInputPlan) {
        name = plan.name
        shape = plan.shape
        generator = plan.generator.rawValue
        seed = plan.seed
    }
}
