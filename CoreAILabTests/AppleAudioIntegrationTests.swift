import Foundation
import Testing
@testable import CoreAILab

struct AppleAudioIntegrationTests {
    @Test
    func exportedWav2Vec2TranscribesThroughCoreAI() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let modelPath = environment["COREAI_WAV2VEC2_MODEL_PATH"],
              let audioPath = environment["COREAI_WAV2VEC2_AUDIO_PATH"] else {
            return
        }

        let engine = AppleWav2Vec2Engine()
        _ = try await engine.loadModel(at: URL(filePath: modelPath))
        let result = try await engine.transcribe(audioAt: URL(filePath: audioPath))

        #expect(!result.transcript.isEmpty)
        #expect(result.audioDurationSeconds > 0)
    }
}
