import CoreAI
import Foundation

enum CoreAISpecializationProfile: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case cpuOnly
    case preferGPU
    case preferNeuralEngine

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic:
            "Automatic"
        case .cpuOnly:
            "CPU only"
        case .preferGPU:
            "Prefer GPU"
        case .preferNeuralEngine:
            "Prefer Neural Engine"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            "Core AI chooses the compute-unit mix that minimizes latency."
        case .cpuOnly:
            "Restricts specialization to the CPU."
        case .preferGPU:
            "Prefers the GPU when available; this does not guarantee exclusive placement."
        case .preferNeuralEngine:
            "Prefers the Neural Engine when available; this does not guarantee exclusive placement."
        }
    }

    var isAvailable: Bool {
        switch self {
        case .automatic, .cpuOnly:
            true
        case .preferGPU:
            ComputeUnitKind.availableKinds.contains(.gpu)
        case .preferNeuralEngine:
            ComputeUnitKind.availableKinds.contains(.neuralEngine)
        }
    }

    var options: SpecializationOptions {
        switch self {
        case .automatic:
            .default
        case .cpuOnly:
            .cpuOnly
        case .preferGPU:
            SpecializationOptions(preferredComputeUnitKind: .gpu)
        case .preferNeuralEngine:
            SpecializationOptions(preferredComputeUnitKind: .neuralEngine)
        }
    }
}
