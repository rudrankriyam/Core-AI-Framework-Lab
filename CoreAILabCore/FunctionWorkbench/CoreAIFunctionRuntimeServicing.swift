import Foundation

protocol CoreAIFunctionRuntimeServicing: CoreAISpecializationServicing {
    func functionContracts() async throws -> [CoreAIFunctionContract]
    func runFunction(
        named functionName: String,
        inputs: [CoreAIFunctionInputPlan]
    ) async throws -> CoreAIFunctionRunResult
    func benchmarkFunction(
        named functionName: String,
        inputs: [CoreAIFunctionInputPlan],
        configuration: CoreAIFunctionBenchmarkConfiguration
    ) async throws -> CoreAIFunctionBenchmarkResult
}
