import Foundation
import Testing
@testable import CoreAILab

struct SpeakerDiarizationIntegrationTests {
    @Test
    func convertedCAMPlusDiarizesImportedMediaThroughCoreAI() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let mediaPath = environment["COREAI_DIARIZATION_MEDIA_PATH"] else {
            return
        }

        let engine = SpeakerDiarizationEngine()
        let modelURL: URL
        if let modelPath = environment["COREAI_CAMPPLUS_MODEL_PATH"] {
            modelURL = URL(filePath: modelPath)
        } else {
            modelURL = try SpeakerDiarizationBundledModel.url()
        }
        let modelInfo = try await engine.loadModel(at: modelURL)
        let result = try await engine.diarize(mediaAt: URL(filePath: mediaPath))

        #expect(modelInfo.embeddingDimension == 192)
        #expect(!result.turns.isEmpty)
        #expect(!result.speakerNames.isEmpty)
        #expect(result.turns.allSatisfy { $0.duration > 0 })
        #expect(result.turns == result.turns.sorted { $0.startTime < $1.startTime })
        #expect((result.evidence?.analysisWindowCount ?? 0) >= result.turns.count)
        print(
            "CAM++ diarization integration: \(result.turns.count) turns, "
                + "\(result.speakerNames.count) speakers, "
                + "\((result.evidence?.totalSeconds ?? 0).formatted(.number.precision(.fractionLength(3)))) seconds"
        )
        for turn in result.turns {
            print(
                "  \(turn.speakerName) "
                    + "\(turn.startTime.formatted(.number.precision(.fractionLength(2))))–"
                    + "\(turn.endTime.formatted(.number.precision(.fractionLength(2)))) "
                    + "cosine \(turn.clusterSimilarity?.formatted(.number.precision(.fractionLength(3))) ?? "new")"
            )
        }
        if let minimum = environment["COREAI_DIARIZATION_MIN_SPEAKERS"].flatMap(Int.init) {
            #expect(result.speakerNames.count >= minimum)
        }
        if let expectedPattern = environment["COREAI_DIARIZATION_EXPECTED_PATTERN"] {
            let expectedNames = expectedPattern.split(separator: ",").map {
                "Speaker \($0.trimmingCharacters(in: .whitespaces))"
            }
            #expect(result.turns.map(\.speakerName) == expectedNames)
        }
    }
}
