import Foundation

enum CoreAILabSection: String, CaseIterable, Hashable, Identifiable {
    case projects
    case appleModels
    case conversion
    case recipeStudio
    case chatterbox
    case diarization
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
        case .recipeStudio:
            "Recipe Studio"
        case .chatterbox:
            "Chatterbox"
        case .diarization:
            "Diarization"
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
        case .recipeStudio:
            "slider.horizontal.3"
        case .chatterbox:
            "waveform"
        case .diarization:
            "person.wave.2"
        case .assetInspector:
            "doc.text.magnifyingglass"
        case .runtime:
            "function"
        }
    }
}
