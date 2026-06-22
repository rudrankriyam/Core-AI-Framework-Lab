enum ChatterboxModelState: Equatable {
    case notLoaded
    case preparing
    case ready(ChatterboxModelInspection)
    case failed(String)

    var title: String {
        switch self {
        case .notLoaded:
            "Bundled model is waiting"
        case .preparing:
            "Optimizing for this Mac"
        case .ready(let inspection):
            inspection.contractValidation.isComplete
                ? "\(inspection.recipe.displayName) is ready"
                : "Model contract is incomplete"
        case .failed:
            "Model preparation failed"
        }
    }

    var detail: String {
        switch self {
        case .notLoaded:
            return "The complete Chatterbox Turbo pipeline ships inside the app."
        case .preparing:
            return "Core AI is specializing and persistently caching four model assets for this Mac."
        case .ready(let inspection):
            if inspection.contractValidation.isComplete {
                return "\(inspection.formattedTotalSize) is bundled and every native entry point is available."
            } else {
                let missing = inspection.contractValidation.missingStages
                    .map { stage in
                        inspection.assets.first { $0.stage == stage }?.displayName
                            ?? stage.rawValue
                    }
                    .sorted()
                    .joined(separator: ", ")
                return "Incomplete bundled stages: \(missing)"
            }
        case .failed(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .notLoaded:
            "shippingbox"
        case .preparing:
            "cpu"
        case .ready(let inspection):
            inspection.contractValidation.isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle"
        case .failed:
            "xmark.octagon"
        }
    }
}
