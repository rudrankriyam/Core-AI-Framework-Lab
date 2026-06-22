import Foundation

struct CoreAIFunctionBenchmarkReport: Identifiable, Sendable, Equatable {
    let id: UUID
    let assetName: String
    let artifactDigest: CoreAIArtifactDigest
    let specializationConfiguration: CoreAISpecializationConfiguration
    let specializationDuration: Duration
    let loadedFromCache: Bool
    let benchmarkConfiguration: CoreAIFunctionBenchmarkConfiguration
    let inputPlans: [CoreAIFunctionInputPlan]
    let result: CoreAIFunctionBenchmarkResult

    init(
        id: UUID = UUID(),
        assetName: String,
        artifactDigest: CoreAIArtifactDigest,
        specializationConfiguration: CoreAISpecializationConfiguration,
        specializationDuration: Duration,
        loadedFromCache: Bool,
        benchmarkConfiguration: CoreAIFunctionBenchmarkConfiguration,
        inputPlans: [CoreAIFunctionInputPlan],
        result: CoreAIFunctionBenchmarkResult
    ) {
        self.id = id
        self.assetName = assetName
        self.artifactDigest = artifactDigest
        self.specializationConfiguration = specializationConfiguration
        self.specializationDuration = specializationDuration
        self.loadedFromCache = loadedFromCache
        self.benchmarkConfiguration = benchmarkConfiguration
        self.inputPlans = inputPlans
        self.result = result
    }
}
