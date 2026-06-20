import Foundation

enum CoreAILabSection: String, CaseIterable, Hashable, Identifiable {
    case projects
    case appleModels
    case conversion
    case chatterbox
    case assetInspector
    case runtime

    var id: Self { self }

    var title: String {
        switch self {
        case .projects:
            "Projects"
        case .appleModels:
            "Apple Models"
        case .conversion:
            "Convert"
        case .chatterbox:
            "Chatterbox"
        case .assetInspector:
            "Asset Inspector"
        case .runtime:
            "Workbench"
        }
    }

    var systemImage: String {
        switch self {
        case .projects:
            "folder"
        case .appleModels:
            "square.stack.3d.up"
        case .conversion:
            "arrow.triangle.2.circlepath"
        case .chatterbox:
            "waveform"
        case .assetInspector:
            "doc.text.magnifyingglass"
        case .runtime:
            "function"
        }
    }
}
