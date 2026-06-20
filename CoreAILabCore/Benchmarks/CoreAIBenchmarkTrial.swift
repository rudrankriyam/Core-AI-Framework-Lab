import Foundation

struct CoreAIBenchmarkTrial: Identifiable, Sendable, Equatable {
    let index: Int
    let duration: Duration

    var id: Int { index }
}
