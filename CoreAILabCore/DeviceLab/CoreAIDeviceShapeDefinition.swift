import Foundation

struct CoreAIDeviceShapeDefinition: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let dimensions: [Int?]
}
