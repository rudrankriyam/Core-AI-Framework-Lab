import Foundation

struct SpeakerDiarizationTurn: Equatable, Identifiable, Sendable {
    let id: Int
    let speakerName: String
    let startTime: Double
    let endTime: Double
    let confidence: Double

    var duration: Double {
        max(0, endTime - startTime)
    }
}
