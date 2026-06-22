import Foundation

struct CoreAIRuntimeComparisonIdentity: Codable, Equatable, Hashable, Identifiable, Sendable {
    let experienceID: String
    let modelIdentifier: String
    let displayName: String

    var id: String {
        "\(experienceID)|\(modelIdentifier)"
    }
}
