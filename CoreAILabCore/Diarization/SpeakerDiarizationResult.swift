import Foundation

struct SpeakerDiarizationResult: Equatable, Sendable {
    let engineName: String
    let turns: [SpeakerDiarizationTurn]
    let generatedAt: Date
    let evidence: SpeakerDiarizationEvidence?

    init(
        engineName: String,
        turns: [SpeakerDiarizationTurn],
        generatedAt: Date,
        evidence: SpeakerDiarizationEvidence? = nil
    ) {
        self.engineName = engineName
        self.turns = turns
        self.generatedAt = generatedAt
        self.evidence = evidence
    }

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
        if abs(time - lastTurn.endTime) < 0.000_001 {
            return lastTurn
        }
        return turns.first { turn in
            time >= turn.startTime && time < turn.endTime
        }
    }
}
