import Foundation

struct CoreAIConversionEnvironmentCheck: Identifiable, Sendable {
    enum Status: Sendable {
        case passed
        case warning
        case failed
    }

    let id: String
    let title: String
    let detail: String
    let status: Status

    var blocksConversion: Bool {
        status == .failed
    }
}
