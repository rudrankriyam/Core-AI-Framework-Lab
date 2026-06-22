import Foundation
import Testing
@testable import CoreAILab

struct AppleAudioIntegrationTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["COREAI_WAV2VEC2_MODEL_PATH"] != nil
                && ProcessInfo.processInfo.environment["COREAI_WAV2VEC2_AUDIO_PATH"] != nil,
            "Requires COREAI_WAV2VEC2_MODEL_PATH and COREAI_WAV2VEC2_AUDIO_PATH."
        )
    )
    func exportedWav2Vec2TranscribesThroughCoreAI() async throws {
        let environment = ProcessInfo.processInfo.environment
        let modelPath = try #require(environment["COREAI_WAV2VEC2_MODEL_PATH"])
        let audioPath = try #require(environment["COREAI_WAV2VEC2_AUDIO_PATH"])

        let engine = AppleWav2Vec2Engine()
        _ = try await engine.loadModel(at: URL(filePath: modelPath))
        let result = try await engine.transcribe(audioAt: URL(filePath: audioPath))

        #expect(!result.transcript.isEmpty)
        #expect(result.audioDurationSeconds > 0)
    }
}
