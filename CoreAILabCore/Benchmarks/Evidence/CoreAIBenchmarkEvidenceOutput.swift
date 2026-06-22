import Foundation

struct CoreAIBenchmarkEvidenceOutput: Codable, Sendable, Equatable {
    let name: String
    let typeDescription: String
    let shape: [Int]
    let elementCount: Int
    let sampledElementCount: Int
    let minimum: Double?
    let maximum: Double?
    let mean: Double?
    let nonFiniteCount: Int

    init(output: CoreAIFunctionOutputSummary) {
        name = output.name
        typeDescription = output.typeDescription
        shape = output.shape
        elementCount = output.elementCount
        sampledElementCount = output.sampledElementCount
        minimum = output.minimum
        maximum = output.maximum
        mean = output.mean
        nonFiniteCount = output.nonFiniteCount
    }
}
