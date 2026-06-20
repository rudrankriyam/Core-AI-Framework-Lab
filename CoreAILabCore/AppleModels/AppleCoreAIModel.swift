import Foundation

struct AppleCoreAIModel: Codable, Hashable, Identifiable, Sendable {
    let shortName: String
    let huggingFaceID: String
    let family: String?
    let type: String?
    let variant: String?
    let compression: String?
    let computePrecision: String?
    let maximumContextLength: Int?
    let experimental: Bool?
    let notes: String?
    let compressionConfig: String?
    let modelType: String?
    let task: String?
    let exportScript: String?
    let platforms: [AppleCoreAIPlatform]?

    var id: String {
        [shortName, variant ?? "all", type ?? modelType ?? "unknown"]
            .joined(separator: "|")
    }

    var category: AppleCoreAIModelCategory {
        if type == "llm" {
            return .language
        }
        if type == "diffusion" {
            return .imageGeneration
        }
        switch modelType {
        case "clap", "wav2vec2", "whisper":
            return .audio
        case "roberta", "t5":
            return .text
        default:
            return .vision
        }
    }

    var supportedPlatforms: [AppleCoreAIPlatform] {
        if let platforms {
            return platforms
        }
        if variant == AppleCoreAIPlatform.iOS.rawValue {
            return [.iOS]
        }
        if variant == AppleCoreAIPlatform.macOS.rawValue {
            return [.macOS]
        }
        return [.iOS, .macOS]
    }

    var runtimeSupport: AppleCoreAIRuntimeSupport {
        if type == "llm" {
            return .languageModel
        }
        if type == "diffusion" {
            return .diffusion
        }
        switch modelType {
        case "efficient-sam", "sam3":
            return .segmentation
        case "yolo":
            return .objectDetection
        default:
            return .genericAsset
        }
    }

    var exportCommand: String {
        CoreAIConversionCommand.displayString(
            executableName: "uv",
            arguments: exportProgramArguments
        )
    }

    var labRecommendedExportCommand: String {
        guard shortName == "yolos-tiny" else {
            return exportCommand
        }
        return "\(exportCommand) --dtype float16"
    }

    var isRunnableInLab: Bool {
        (runtimeSupport == .objectDetection && shortName == "yolos-tiny")
            || segmentationExample != nil
            || languageExample != nil
    }

    var segmentationExample: AppleSegmentationExample? {
        AppleSegmentationExample(shortName: shortName)
    }

    var languageExample: AppleLanguageExample? {
        AppleLanguageExample(shortName: shortName)
    }

    var recipePath: String {
        if let exportScript {
            return String(exportScript.dropLast("/export.py".count))
        }
        let folder: String
        switch family {
        case "gpt-oss":
            folder = "gpt_oss"
        case "qwen2.5":
            folder = "qwen2"
        case "qwen3-moe":
            folder = "qwen3_moe"
        case "stable-diffusion-3":
            folder = "stable-diffusion"
        default:
            folder = family ?? shortName
        }
        return "models/\(folder)"
    }

    var registryType: String {
        type ?? "utility"
    }

    var exportProgramArguments: [String] {
        if type == "llm" {
            return ["run", "coreai.llm.export"] + exportArguments
        }
        if type == "diffusion" {
            return ["run", "coreai.diffusion.export"] + exportArguments
        }
        guard let exportScript else {
            return []
        }
        return ["run", exportScript, "--model", huggingFaceID]
    }

    var supportedConversionPrecisions: [CoreAIConversionPrecision] {
        guard let exportScript else { return [] }

        switch exportScript {
        case "models/depth-anything/export.py":
            return [.float32]
        case "models/clap/export.py",
             "models/sam3/export.py",
             "models/t5/export.py",
             "models/wav2vec2/export.py":
            return [.float16, .float32]
        default:
            return CoreAIConversionPrecision.allCases
        }
    }

    func recipeURL(sourceRevision: String) -> URL? {
        URL(
            string: "https://github.com/apple/coreai-models/tree/\(sourceRevision)/\(recipePath)"
        )
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return [shortName, huggingFaceID, family, modelType, task]
            .compactMap { $0 }
            .contains { $0.localizedStandardContains(query) }
    }

    private var exportArguments: [String] {
        var arguments = [huggingFaceID]
        if let compressionConfig {
            arguments.append(contentsOf: ["--compression-config", compressionConfig])
        } else if let compression {
            arguments.append(contentsOf: ["--compression", compression])
        }
        if let computePrecision {
            arguments.append(contentsOf: ["--compute-precision", computePrecision])
        }
        if let maximumContextLength {
            arguments.append(contentsOf: ["--max-context-length", String(maximumContextLength)])
        }
        if type == "llm", variant == AppleCoreAIPlatform.iOS.rawValue {
            arguments.append(contentsOf: ["--platform", "iOS"])
        }
        return arguments
    }

    enum CodingKeys: String, CodingKey {
        case shortName = "short_name"
        case huggingFaceID = "hf_id"
        case family
        case type
        case variant
        case compression
        case computePrecision = "compute_precision"
        case maximumContextLength = "max_context_length"
        case experimental
        case notes
        case compressionConfig = "compression_config"
        case modelType = "model_type"
        case task
        case exportScript = "export_script"
        case platforms
    }
}
