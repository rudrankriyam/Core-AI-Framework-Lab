enum CoreAIRecipeRewriteCatalog {
    static let builtIn: [CoreAIRecipeRewrite] = [
        CoreAIRecipeRewrite(
            id: "unbiased_variance_moments",
            title: "Unbiased variance from moments",
            operatorNames: ["aten.var.correction"],
            strategy: .sourceRewrite,
            summary: "Replace correction-based variance with explicit mean, squared residuals, and sample-count scaling.",
            evidence: "Used by the checked-in Chatterbox speaker-encoder adapter."
        ),
        CoreAIRecipeRewrite(
            id: "fixed_filter_fourier",
            title: "Fixed-filter STFT and ISTFT",
            operatorNames: ["aten.stft", "aten.istft"],
            strategy: .sourceRewrite,
            summary: "Express the fixed Fourier basis with convolution and transpose-convolution primitives.",
            evidence: "Used by the checked-in Chatterbox vocoder adapter with parity tests."
        ),
        CoreAIRecipeRewrite(
            id: "explicit_reflection_padding",
            title: "Explicit reflection padding",
            operatorNames: ["aten.reflection_pad1d"],
            strategy: .decomposition,
            summary: "Construct reflected borders with slicing, reversal, and concatenation.",
            evidence: "Used by the checked-in Chatterbox vocoder adapter."
        ),
        CoreAIRecipeRewrite(
            id: "immutable_state_slice_update",
            title: "Immutable state slice update",
            operatorNames: ["chatterbox_coreai::immutable_slice_update.default"],
            strategy: .customLowering,
            summary: "Lower a functional cache update to Core AI slice_update while retaining explicit state ownership.",
            evidence: "Mirrors the registered lowering in Conversion/Chatterbox/coreai_state.py."
        )
    ]

    static func rewrite(id: String) -> CoreAIRecipeRewrite? {
        builtIn.first { $0.id == id }
    }
}
