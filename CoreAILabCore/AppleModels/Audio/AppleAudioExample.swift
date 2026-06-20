import Foundation

enum AppleAudioExample: String, Hashable, Sendable {
    case wav2Vec2

    init?(shortName: String) {
        guard shortName == "wav2vec2-base" else { return nil }
        self = .wav2Vec2
    }

    init?(modelAssetURL: URL) {
        guard modelAssetURL.lastPathComponent.lowercased().contains("wav2vec2") else {
            return nil
        }
        self = .wav2Vec2
    }

    var title: String {
        "Wav2Vec2 Base"
    }

    var playgroundButtonTitle: String {
        "Open \(title) Playground"
    }

    var exportCommand: String {
        "uv run models/wav2vec2/export.py --model wav2vec2_asr_base_960h --dtype float16"
    }
}
