import Foundation

struct CoreAIBenchmarkEvidenceSpecialization: Codable, Sendable, Equatable {
    let profile: String
    let preferredComputeUnit: String?
    let expectFrequentReshapes: Bool

    init(configuration: CoreAISpecializationConfiguration) {
        profile = configuration.profile.rawValue
        expectFrequentReshapes = configuration.expectFrequentReshapes
        switch configuration.profile {
        case .preferGPU:
            preferredComputeUnit = "gpu"
        case .preferNeuralEngine:
            preferredComputeUnit = "neuralEngine"
        case .automatic, .cpuOnly:
            preferredComputeUnit = nil
        }
    }
}
