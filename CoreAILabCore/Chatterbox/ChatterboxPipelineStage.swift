enum ChatterboxPipelineStage: String, CaseIterable, Identifiable, Sendable {
    case t3Embeddings
    case t3Transformer
    case s3gen
    case vocoder

    var id: String { rawValue }

    var assetFilename: String {
        switch self {
        case .t3Embeddings:
            "ChatterboxTurboT3Embeddings.aimodel"
        case .t3Transformer:
            "ChatterboxTurboT3TransformerInt4.aimodel"
        case .s3gen:
            "ChatterboxTurboS3Gen.aimodel"
        case .vocoder:
            "ChatterboxTurboVocoder.aimodel"
        }
    }

    var requiredFunctionNames: Set<String> {
        switch self {
        case .t3Embeddings, .t3Transformer:
            ["prefill", "decode"]
        case .s3gen:
            ["main"]
        case .vocoder:
            ["vocoder"]
        }
    }

    var title: String {
        switch self {
        case .t3Embeddings:
            "T3 embeddings"
        case .t3Transformer:
            "T3 transformer"
        case .s3gen:
            "S3Gen flow"
        case .vocoder:
            "HiFT vocoder"
        }
    }

    var detail: String {
        switch self {
        case .t3Embeddings:
            "Text and generated-speech embeddings with the built-in voice prompt."
        case .t3Transformer:
            "INT4 autoregressive speech-token model with persistent key/value caches."
        case .s3gen:
            "Speech tokens to a 512-frame mel spectrogram."
        case .vocoder:
            "Mel spectrogram to 24 kHz waveform audio."
        }
    }
}
