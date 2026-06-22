enum ChatterboxPipelineStage: String, CaseIterable, Identifiable, Sendable {
    case t3Embeddings
    case t3Transformer
    case s3gen
    case vocoder

    var id: String { rawValue }
}
