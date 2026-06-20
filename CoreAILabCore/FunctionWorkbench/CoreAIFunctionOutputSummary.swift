import Foundation

struct CoreAIFunctionOutputSummary: Identifiable, Sendable, Equatable {
    let name: String
    let typeDescription: String
    let shape: [Int]
    let strides: [Int]
    let elementCount: Int
    let sampledElementCount: Int
    let minimum: Double?
    let maximum: Double?
    let mean: Double?
    let nonFiniteCount: Int
    let preview: [String]

    var id: String { name }
}
