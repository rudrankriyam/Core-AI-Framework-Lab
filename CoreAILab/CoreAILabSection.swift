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

    static let library: [Self] = [.projects, .appleModels, .recipes]
    static let build: [Self] = [.conversion, .recipeStudio]
    static let run: [Self] = [.chatterbox, .diarization, .runtime]
    static let validate: [Self] = [.assetInspector, .deviceLab]

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

    var summary: String {
        switch self {
        case .projects:
            "Organize imported artifacts, provenance, runs, and evidence."
        case .appleModels:
            "Browse Apple's pinned Core AI export recipes."
        case .recipes:
            "Review curated recipes and inspect imported bundles."
        case .conversion:
            "Export a Core AI model from an Apple recipe."
        case .recipeStudio:
            "Author and validate recipe and pipeline contracts."
        case .chatterbox:
            "Generate speech with the bundled Core AI pipeline."
        case .diarization:
            "Build an anonymous speaker timeline from local media."
        case .assetInspector:
            "Inspect functions, compute types, and specialization caches."
        case .runtime:
            "Run task adapters and record evidence-backed timing."
        case .deviceLab:
            "Plan iPhone delivery and import physical-device evidence."
        }
    }
}
