import Foundation

enum CoreAILabSection: String, CaseIterable, Hashable, Identifiable {
    case appleModels
    case chatterbox
    case assetInspector
    case runtime

    var id: Self { self }

    var title: String {
        switch self {
        case .appleModels:
            "Apple Models"
        case .chatterbox:
            "Chatterbox"
        case .assetInspector:
            "Asset Inspector"
        case .runtime:
            "Runtime"
        }
    }

    var systemImage: String {
        switch self {
        case .appleModels:
            "square.stack.3d.up"
        case .chatterbox:
            "waveform"
        case .assetInspector:
            "doc.text.magnifyingglass"
        case .runtime:
            "cpu"
        }
    }
}
