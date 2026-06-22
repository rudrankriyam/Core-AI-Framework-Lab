import Foundation

struct CoreAIBenchmarkEvidenceTiming: Codable, Sendable, Equatable, Comparable {
    let seconds: Int64
    let attoseconds: Int64

    init(duration: Duration) {
        let components = duration.components
        seconds = components.seconds
        attoseconds = components.attoseconds
    }

    var secondsValue: Double {
        Double(seconds)
            + Double(attoseconds) / 1_000_000_000_000_000_000
    }

    func validate(field: String) throws {
        guard seconds >= 0,
              attoseconds >= 0,
              attoseconds < 1_000_000_000_000_000_000 else {
            throw CoreAIBenchmarkEvidenceError.invalidField(field)
        }
    }

    static func < (
        lhs: CoreAIBenchmarkEvidenceTiming,
        rhs: CoreAIBenchmarkEvidenceTiming
    ) -> Bool {
        if lhs.seconds != rhs.seconds {
            return lhs.seconds < rhs.seconds
        }
        return lhs.attoseconds < rhs.attoseconds
    }
}
