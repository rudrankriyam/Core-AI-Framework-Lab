import Foundation

enum SpeakerDiarizationStubEngine {
    static let name = "Stub diarization engine"

    static func makeResult(durationSeconds: Double) -> SpeakerDiarizationResult {
        let boundedDuration = max(durationSeconds, 1)
        let speakerCount = boundedDuration > 90 ? 3 : 2
        let targetTurnLength = max(8, min(28, boundedDuration / 8))
        var turns: [SpeakerDiarizationTurn] = []
        var start = Double.zero
        var index = 0

        while start < boundedDuration {
            let speakerIndex = (index % speakerCount) + 1
            let turnLength = targetTurnLength + Double((index % 3) * 3)
            let end = min(boundedDuration, start + turnLength)
            turns.append(
                SpeakerDiarizationTurn(
                    id: index,
                    speakerName: "Speaker \(speakerIndex)",
                    startTime: start,
                    endTime: end,
                    confidence: 0.82 + Double(index % 4) * 0.03
                )
            )
            start = end
            index += 1
        }

        return SpeakerDiarizationResult(
            engineName: name,
            turns: turns,
            generatedAt: .now
        )
    }
}
