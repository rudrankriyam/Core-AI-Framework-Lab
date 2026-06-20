import Foundation

enum AppleDiffusionExample: String, Hashable, Sendable {
    case stableDiffusion15
    case stableDiffusion21
    case stableDiffusion35
    case flux2Klein4B
    case exportedBundle

    init?(shortName: String) {
        switch shortName {
        case "sd-1.5":
            self = .stableDiffusion15
        case "sd-2.1":
            self = .stableDiffusion21
        case "sd-3.5-medium":
            self = .stableDiffusion35
        case "flux2-klein-4b":
            self = .flux2Klein4B
        default:
            return nil
        }
    }

    init(resourceBundleURL: URL) {
        let name = resourceBundleURL.lastPathComponent.lowercased()
        if name.contains("flux") {
            self = .flux2Klein4B
        } else if name.contains("3_5") || name.contains("3.5") {
            self = .stableDiffusion35
        } else if name.contains("2_1") || name.contains("2.1") {
            self = .stableDiffusion21
        } else if name.contains("1_5") || name.contains("1.5") {
            self = .stableDiffusion15
        } else {
            self = .exportedBundle
        }
    }

    var title: String {
        switch self {
        case .stableDiffusion15:
            "Stable Diffusion 1.5"
        case .stableDiffusion21:
            "Stable Diffusion 2.1"
        case .stableDiffusion35:
            "Stable Diffusion 3.5 Medium"
        case .flux2Klein4B:
            "FLUX.2 Klein 4B"
        case .exportedBundle:
            "Core AI Diffusion"
        }
    }

    var playgroundButtonTitle: String {
        "Open (title) Playground"
    }
}
