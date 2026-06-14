struct ChatterboxGenerationRequest: Sendable {
    let text: String
    let seed: UInt64
    let maximumGeneratedTokens: Int

    init(
        text: String,
        seed: UInt64 = 67,
        maximumGeneratedTokens: Int = 253
    ) {
        self.text = text
        self.seed = seed
        self.maximumGeneratedTokens = maximumGeneratedTokens
    }
}
