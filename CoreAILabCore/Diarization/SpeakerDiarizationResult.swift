import Foundation

struct SpeakerDiarizationResult: Equatable, Sendable {
    let engineName: String
    let turns: [SpeakerDiarizationTurn]
    let generatedAt: Date

    var speakerNames: [String] {
        var names: [String] = []
        for turn in turns where !names.contains(turn.speakerName) {
            names.append(turn.speakerName)
        }
        return names
    }

    func turn(at time: Double) -> SpeakerDiarizationTurn? {
        guard let lastTurn = turns.last else {
            return nil
        }
        if time >= lastTurn.endTime {
            return lastTurn
        }
        return turns.first { turn in
            time >= turn.startTime && time < turn.endTime
        }
    }
}
