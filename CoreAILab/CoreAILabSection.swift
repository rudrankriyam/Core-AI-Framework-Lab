import Foundation

enum CoreAILabSection: String, CaseIterable, Hashable, Identifiable {
    case projects
    case appleModels
    case recipes
    case conversion
    case recipeStudio
    case chatterbox
    case diarization
    case assetInspector
    case runtime
    case deviceLab

    static let tools: [Self] = [.assetInspector, .runtime, .deviceLab]
    static let workspaces = allCases.filter { !tools.contains($0) }

    var id: Self { self }

    var title: String {
        switch self {
        case .projects:
            "Projects"
        case .appleModels:
            "Apple Models"
        case .recipes:
            "Recipes"
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
            "Runtime Studio"
        case .deviceLab:
            "Device Lab"
        }
    }

    var systemImage: String {
        switch self {
        case .projects:
            "folder"
        case .appleModels:
            "square.stack.3d.up"
        case .recipes:
            "books.vertical"
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
            "play.square.stack"
        case .deviceLab:
            "iphone.gen3"
        }
    }
}
