enum ChatterboxFunctionContract {
    static func validate(
        functionNamesByStage: [ChatterboxPipelineStage: Set<String>],
        recipe: ChatterboxRecipeContract
    ) -> ChatterboxContractValidation {
        let present = Set(ChatterboxPipelineStage.allCases.filter { stage in
            guard let functionNames = functionNamesByStage[stage],
                  let resolvedStage = try? recipe.resolvedStage(stage) else {
                return false
            }
            return resolvedStage.requiredFunctionNames.isSubset(of: functionNames)
        })
        let missing = Set(ChatterboxPipelineStage.allCases).subtracting(present)

        return ChatterboxContractValidation(
            presentStages: present,
            missingStages: missing
        )
    }
}
