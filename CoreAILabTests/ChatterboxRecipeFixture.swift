import Foundation
@testable import CoreAILab

enum ChatterboxRecipeFixture {
    static let manifest = CoreAIRecipeManifest(
        id: "resemble/chatterbox-turbo",
        revision: "chatterbox-tts-0.1.7",
        displayName: "Chatterbox Turbo",
        summary: "Expressive text-to-speech running locally through Apple Core AI.",
        systemImage: "waveform.circle.fill",
        source: CoreAIRecipeSourceManifest(
            repository: "ResembleAI/chatterbox",
            revision: "chatterbox-tts-0.1.7",
            license: "MIT"
        ),
        defaultTargetID: "mac-gpu",
        targets: [
            CoreAITargetManifest(
                id: "mac-gpu",
                displayName: "Mac GPU",
                platform: .macOS,
                minimumOSVersion: "27.0",
                preferredComputeUnit: .gpu,
                expectsFrequentReshapes: false
            )
        ],
        artifacts: [
            CoreAIArtifactManifest(
                id: "tokenizer",
                displayName: "Hugging Face tokenizer",
                kind: .tokenizer,
                relativePath: "tokenizer"
            ),
            CoreAIArtifactManifest(
                id: "t3Embeddings",
                displayName: "T3 embeddings",
                kind: .modelAsset,
                relativePath: "ChatterboxTurboT3Embeddings.aimodel",
                precision: "FP16",
                requiredEntrypoints: ["prefill", "decode"]
            ),
            CoreAIArtifactManifest(
                id: "t3Transformer",
                displayName: "T3 transformer",
                kind: .modelAsset,
                relativePath: "ChatterboxTurboT3TransformerInt4.aimodel",
                precision: "mixed INT4/INT8/FP16",
                requiredEntrypoints: ["prefill", "decode"]
            ),
            CoreAIArtifactManifest(
                id: "s3gen",
                displayName: "S3Gen flow",
                kind: .modelAsset,
                relativePath: "ChatterboxTurboS3Gen.aimodel",
                precision: "FP16",
                requiredEntrypoints: ["main"]
            ),
            CoreAIArtifactManifest(
                id: "vocoder",
                displayName: "HiFT vocoder",
                kind: .modelAsset,
                relativePath: "ChatterboxTurboVocoder.aimodel",
                precision: "FP16",
                requiredEntrypoints: ["vocoder"]
            )
        ],
        pipeline: CoreAIRecipePipelineManifest(
            experience: .textToSpeech,
            tokenizerArtifactID: "tokenizer",
            stages: [
                CoreAIRecipePipelineStageManifest(
                    id: "t3Embeddings",
                    displayName: "T3 embeddings",
                    detail: "Text and generated-speech embeddings with the built-in voice prompt.",
                    artifactID: "t3Embeddings",
                    entrypoints: ["prefill": "prefill", "decode": "decode"]
                ),
                CoreAIRecipePipelineStageManifest(
                    id: "t3Transformer",
                    displayName: "T3 transformer",
                    detail: "INT4 autoregressive speech-token model with persistent key/value caches.",
                    artifactID: "t3Transformer",
                    entrypoints: ["prefill": "prefill", "decode": "decode"]
                ),
                CoreAIRecipePipelineStageManifest(
                    id: "s3gen",
                    displayName: "S3Gen flow",
                    detail: "Speech tokens to a 512-frame mel spectrogram.",
                    artifactID: "s3gen",
                    entrypoints: ["generateMel": "main"]
                ),
                CoreAIRecipePipelineStageManifest(
                    id: "vocoder",
                    displayName: "HiFT vocoder",
                    detail: "Mel spectrogram to 24 kHz waveform audio.",
                    artifactID: "vocoder",
                    entrypoints: ["synthesizeWaveform": "vocoder"]
                )
            ]
        ),
        capacity: capacity()
    )

    static func contract() throws -> ChatterboxRecipeContract {
        try ChatterboxRecipeContract(manifest: manifest)
    }

    static func capacity(
        maximumGeneratedTokens: Int = 253,
        speechTokenBufferCount: Int = 256,
        endSilenceTokenCount: Int = 3,
        generatedMelFrameCount: Int = 512,
        sampleRate: Int = 24_000
    ) -> CoreAICapacityManifest {
        CoreAICapacityManifest(
            maximumInputTokens: 256,
            maximumGeneratedTokens: maximumGeneratedTokens,
            maximumContextTokens: 768,
            requiresStopSignal: true,
            parameters: [
                "t3LayerCount": 24,
                "t3HeadCount": 16,
                "t3HeadDimension": 64,
                "t3StartSpeechToken": 6_561,
                "t3StopSpeechToken": 6_562,
                "speechTokenBufferCount": speechTokenBufferCount,
                "endSilenceTokenCount": endSilenceTokenCount,
                "silenceToken": 4_299,
                "melNoiseFrameCount": 1_012,
                "generatedMelFrameCount": generatedMelFrameCount,
                "melFramesPerSpeechToken": 2,
                "sourceChannelCount": 9,
                "samplesPerMelFrame": 480,
                "sampleRate": sampleRate
            ]
        )
    }
}
