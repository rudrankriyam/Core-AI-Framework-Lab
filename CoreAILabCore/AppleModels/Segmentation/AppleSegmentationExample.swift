import Foundation

enum AppleSegmentationExample: String, Hashable, Sendable {
    case efficientSAM
    case sam3

    init?(shortName: String) {
        switch shortName {
        case "efficient-sam-vitt":
            self = .efficientSAM
        case "sam3":
            self = .sam3
        default:
            return nil
        }
    }

    init?(resourceBundleURL: URL) {
        let name = resourceBundleURL.lastPathComponent.lowercased()
        if name.hasPrefix("efficient_sam_vitt_") {
            self = .efficientSAM
        } else if name.hasPrefix("sam3_") {
            self = .sam3
        } else {
            return nil
        }
    }

    var title: String {
        switch self {
        case .efficientSAM:
            "EfficientSAM"
        case .sam3:
            "SAM 3"
        }
    }

    var playgroundButtonTitle: String {
        "Open \(title) Playground"
    }

    var usesTextPrompt: Bool {
        self == .sam3
    }

    var exportCommand: String {
        switch self {
        case .efficientSAM:
            "uv run models/efficient-sam/export.py --dtype float16"
        case .sam3:
            "uv run models/sam3/export.py --dtype float16"
        }
    }

    var modelImportDescription: String {
        switch self {
        case .efficientSAM:
            "Import the segmenter bundle produced by Apple's EfficientSAM recipe."
        case .sam3:
            "Accept Meta's gated SAM 3 license on Hugging Face, authenticate with `hf auth login`, run Apple's export, then import the bundle with its tokenizer folder. Core AI Lab never reads or stores your token."
        }
    }
}
