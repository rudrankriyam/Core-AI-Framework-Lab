import Foundation

enum AppleLanguageExample: String, Hashable, Sendable {
    case qwen3_0_6B

    init?(shortName: String) {
        guard shortName == "qwen3-0.6b" else { return nil }
        self = .qwen3_0_6B
    }

    init?(resourceBundleURL: URL) {
        let name = resourceBundleURL.lastPathComponent.lowercased()
        guard name.contains("qwen3") && (name.contains("0_6b") || name.contains("0.6b")) else {
            return nil
        }
        self = .qwen3_0_6B
    }

    var title: String {
        "Qwen3 0.6B"
    }

    var playgroundButtonTitle: String {
        "Open \(title) Playground"
    }

    var macOSExportCommand: String {
        "uv run coreai.llm.export Qwen/Qwen3-0.6B --compression 4bit --compute-precision float16 --max-context-length 8192"
    }

    var iOSExportCommand: String {
        "uv run coreai.llm.export Qwen/Qwen3-0.6B --compression-config models/qwen3/qwen3_0_6b_mixed_4bit_8bit.yaml --compute-precision float16 --max-context-length 4096 --platform iOS"
    }
}
