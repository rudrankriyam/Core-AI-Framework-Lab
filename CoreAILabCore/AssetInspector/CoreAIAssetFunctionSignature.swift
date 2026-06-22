import Foundation

struct CoreAIAssetFunctionSignature: Codable, Identifiable, Sendable, Equatable {
    let name: String
    let inputs: [CoreAIAssetValueSignature]
    let states: [CoreAIAssetValueSignature]
    let outputs: [CoreAIAssetValueSignature]

    var id: String { name }
}
