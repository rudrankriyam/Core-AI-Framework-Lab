import Foundation
import Testing
@testable import CoreAILab

struct ChatterboxFunctionContractTests {
    @Test
    func completeContractRecognizesEveryStage() throws {
        let recipe = try ChatterboxRecipeFixture.contract()
        let functions = Dictionary(
            uniqueKeysWithValues: try ChatterboxPipelineStage.allCases.map {
                ($0, try recipe.resolvedStage($0).requiredFunctionNames)
            }
        )
        let validation = ChatterboxFunctionContract.validate(
            functionNamesByStage: functions,
            recipe: recipe
        )

        #expect(validation.isComplete)
        #expect(validation.missingStages.isEmpty)
    }

    @Test
    func incompleteContractReportsMissingStages() throws {
        let recipe = try ChatterboxRecipeFixture.contract()
        let validation = ChatterboxFunctionContract.validate(
            functionNamesByStage: [
                .t3Embeddings: ["prefill", "decode"],
                .vocoder: [],
            ],
            recipe: recipe
        )

        #expect(!validation.isComplete)
        #expect(validation.presentStages == [.t3Embeddings])
        #expect(validation.missingStages.contains(.vocoder))
    }

    @Test
    func textNormalizationMatchesChatterbox() {
        #expect(
            ChatterboxTextNormalizer.normalize("hello  there: friend")
                == "Hello there, friend."
        )
        #expect(
            ChatterboxTextNormalizer.normalize("Already done!")
                == "Already done!"
        )
    }

    @Test
    func waveWriterProducesPCMHeader() throws {
        let data = try ChatterboxWaveFile.data(
            samples: [0, 0.5, -0.5],
            sampleRate: 24_000
        )
        #expect(String(data: data.prefix(4), encoding: .ascii) == "RIFF")
        #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")
        #expect(data.count == 50)
    }

    @Test
    func waveWriterRejectsUnrepresentableSampleRates() {
        #expect(throws: ChatterboxCoreAIError.self) {
            _ = try ChatterboxWaveFile.data(
                samples: [0],
                sampleRate: .max
            )
        }
    }

    @Test
    func waveWriterRejectsNonFiniteSamples() {
        #expect(throws: ChatterboxCoreAIError.self) {
            _ = try ChatterboxWaveFile.data(
                samples: [.nan],
                sampleRate: 24_000
            )
        }
    }

    @Test
    func samplerReturnsAValidTokenDeterministically() throws {
        let logits: [Float] = [0.1, 1.4, -0.2, 0.8]
        let firstRandom = ChatterboxRandomGenerator(seed: 7)
        let secondRandom = ChatterboxRandomGenerator(seed: 7)

        let first = try ChatterboxSampler.sample(
            logits: logits,
            generatedTokens: [],
            random: firstRandom,
            topK: logits.count
        )
        let second = try ChatterboxSampler.sample(
            logits: logits,
            generatedTokens: [],
            random: secondRandom,
            topK: logits.count
        )

        #expect(logits.indices.contains(first))
        #expect(first == second)
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["RUN_CHATTERBOX_INTEGRATION"] == "1",
            "Requires RUN_CHATTERBOX_INTEGRATION=1."
        )
    )
    func bundledCoreAISmokeTest() async throws {
        let engine = ChatterboxCoreAIEngine(bundle: .main)
        let inspection = try await engine.prepareBundledModels()
        #expect(inspection.contractValidation.isComplete)

        let result = try await Task(priority: .userInitiated) {
            try await engine.synthesize(
                ChatterboxGenerationRequest(
                    text: "Oh, that's hilarious! [chuckle] This voice is running entirely on your Mac with Core AI."
                )
            )
        }.value
        #expect(result.generatedTokenCount > 125)
        #expect(result.audioDuration > 5.12)
        print(
            """
            Chatterbox benchmark
              total: \(result.elapsedTime)
              audio: \(result.audioDuration)
              RTF: \(result.realTimeFactor)
              text: \(result.metrics.textPreparation)
              T3 setup: \(result.metrics.t3Setup)
              T3 prefill: \(result.metrics.t3Prefill)
              T3 embedding inference: \(result.metrics.t3EmbeddingInference)
              T3 transformer inference: \(result.metrics.t3TransformerInference)
              T3 decode inference: \(result.metrics.t3DecodeInference)
              T3 decode host: \(result.metrics.t3DecodeHost)
              S3 setup: \(result.metrics.s3GenSetup)
              S3 noise: \(result.metrics.s3GenNoise)
              S3 inference: \(result.metrics.s3GenInference)
              vocoder setup: \(result.metrics.vocoderSetup)
              vocoder noise: \(result.metrics.vocoderNoise)
              vocoder inference: \(result.metrics.vocoderInference)
              postprocessing: \(result.metrics.audioPostprocessing)
            """
        )

        do {
            _ = try await engine.synthesize(
                ChatterboxGenerationRequest(
                    text: "This request must stop at the configured generation ceiling.",
                    maximumGeneratedTokens: 1
                )
            )
            Issue.record("Expected the generation ceiling to reject clipped audio.")
        } catch ChatterboxCoreAIError.generationLimitReached {
            // Expected: reaching the budget must never produce a partial WAV.
        }

        if let outputPath = ProcessInfo.processInfo.environment[
            "CHATTERBOX_SMOKE_OUTPUT"
        ] {
            let destination = URL(fileURLWithPath: outputPath)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(
                at: result.audioURL,
                to: destination
            )
        }
    }
}
