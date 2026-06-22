import Foundation

struct CoreAIDeviceShapeAuthoringRequest: Codable, Equatable, Sendable {
    let requestedContextTokens: Int?
    let maximumContextTokens: Int?
    let expectsFrequentReshapes: Bool
    let shapes: [CoreAIDeviceShapeDefinition]
}
