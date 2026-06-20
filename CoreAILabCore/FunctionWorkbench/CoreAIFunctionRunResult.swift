import Foundation

struct CoreAIFunctionRunResult: Sendable, Equatable {
    let functionName: String
    let duration: Duration
    let outputs: [CoreAIFunctionOutputSummary]
}
