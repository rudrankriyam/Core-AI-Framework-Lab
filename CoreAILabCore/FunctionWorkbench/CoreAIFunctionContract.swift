import Foundation

struct CoreAIFunctionContract: Identifiable, Sendable, Equatable {
    let name: String
    let inputs: [CoreAIFunctionValueContract]
    let states: [CoreAIFunctionValueContract]
    let outputs: [CoreAIFunctionValueContract]
    let unsupportedReason: String?

    var id: String { name }

    var isRunnable: Bool {
        unsupportedReason == nil
    }
}
