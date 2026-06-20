import Foundation

struct CoreAIFunctionBenchmarkReport: Identifiable, Sendable, Equatable {
    let id: UUID
    let assetName: String
    let specializationConfiguration: CoreAISpecializationConfiguration
    let specializationDuration: Duration
    let loadedFromCache: Bool
    let inputPlans: [CoreAIFunctionInputPlan]
    let result: CoreAIFunctionBenchmarkResult

    init(
        id: UUID = UUID(),
        assetName: String,
        specializationConfiguration: CoreAISpecializationConfiguration,
        specializationDuration: Duration,
        loadedFromCache: Bool,
        inputPlans: [CoreAIFunctionInputPlan],
        result: CoreAIFunctionBenchmarkResult
    ) {
        self.id = id
        self.assetName = assetName
        self.specializationConfiguration = specializationConfiguration
        self.specializationDuration = specializationDuration
        self.loadedFromCache = loadedFromCache
        self.inputPlans = inputPlans
        self.result = result
    }
}
