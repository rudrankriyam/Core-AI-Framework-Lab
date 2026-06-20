import Foundation

struct CoreAISpecializationResult: Sendable, Equatable {
    let duration: Duration
    let loadedFromCache: Bool
    let functionNames: [String]
    let bookmarkData: Data
}
