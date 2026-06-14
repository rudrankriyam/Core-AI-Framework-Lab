struct ChatterboxContractValidation: Sendable, Equatable {
    let presentStages: Set<ChatterboxPipelineStage>
    let missingStages: Set<ChatterboxPipelineStage>

    static let empty = ChatterboxContractValidation(
        presentStages: [],
        missingStages: Set(ChatterboxPipelineStage.allCases)
    )

    var isComplete: Bool {
        missingStages.isEmpty
    }
}
