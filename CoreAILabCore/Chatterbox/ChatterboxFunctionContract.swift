enum ChatterboxFunctionContract {
    static func validate(
        functionNamesByStage: [ChatterboxPipelineStage: Set<String>]
    ) -> ChatterboxContractValidation {
        let present = Set(ChatterboxPipelineStage.allCases.filter { stage in
            guard let functionNames = functionNamesByStage[stage] else {
                return false
            }
            return stage.requiredFunctionNames.isSubset(of: functionNames)
        })
        let missing = Set(ChatterboxPipelineStage.allCases).subtracting(present)

        return ChatterboxContractValidation(
            presentStages: present,
            missingStages: missing
        )
    }
}
