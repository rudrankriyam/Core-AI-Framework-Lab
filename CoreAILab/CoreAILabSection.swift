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

    var areaTitle: String {
        switch self {
        case .projects, .appleModels, .recipes:
            "Library"
        case .conversion, .recipeStudio:
            "Build"
        case .chatterbox, .diarization, .runtime:
            "Run"
        case .assetInspector, .deviceLab:
            "Validate"
        }
    }

    var workflowSteps: [String] {
        switch self {
        case .projects:
            [
                "Create or open a project",
                "Import checked artifacts",
                "Review runs and evidence"
            ]
        case .appleModels:
            [
                "Choose an Apple recipe",
                "Review its requirements and provenance",
                "Convert it or open its runtime"
            ]
        case .recipes:
            [
                "Choose a curated recipe",
                "Review its code and provenance",
                "Import the approved bundle"
            ]
        case .conversion:
            [
                "Configure the recipe",
                "Validate the local environment",
                "Convert and verify the artifacts"
            ]
        case .recipeStudio:
            [
                "Define the source and contracts",
                "Resolve unsupported operations",
                "Compose and validate the pipeline"
            ]
        case .chatterbox:
            [
                "Prepare the bundled models",
                "Write expressive speech",
                "Generate and review local audio"
            ]
        case .diarization:
            [
                "Import local media",
                "Analyze anonymous speakers",
                "Review the speaker timeline"
            ]
        case .assetInspector:
            [
                "Open an .aimodel package",
                "Inspect descriptors and compute types",
                "Specialize and verify cache state"
            ]
        case .runtime:
            [
                "Choose an experience",
                "Provide its assets and inputs",
                "Run and record measured evidence"
            ]
        case .deviceLab:
            [
                "Define the physical target",
                "Plan asset delivery",
                "Import device-run evidence"
            ]
        }
    }

    var evidenceBoundary: String {
        switch self {
        case .projects:
            "Checksummed storage preserves artifacts and provenance. A stored artifact is not a runtime measurement."
        case .appleModels:
            "Catalog entries describe pinned Apple recipes. Core AI Lab does not bundle the source model weights."
        case .recipes:
            "A recipe documents a conversion path. Review its code and upstream license before approving an import."
        case .conversion:
            "The command, process log, checksums, and validation findings are evidence. A planned command is not a completed conversion."
        case .recipeStudio:
            "Structural validation checks the authored contract. It does not prove that conversion or runtime execution will succeed."
        case .chatterbox:
            "Generated audio comes from the bundled local pipeline. Cache reuse does not prove a speed or memory improvement."
        case .diarization:
            "Speaker labels are anonymous clusters inferred from local media, not verified identities."
        case .assetInspector:
            "Descriptors and cache state come from Core AI. A preferred compute unit does not prove hardware placement."
        case .runtime:
            "Only completed runs produce measured timing. Setup choices and comparison identities remain contextual metadata."
        case .deviceLab:
            "Target preferences and storage plans are proposals. Imported runner output is the physical-device evidence."
        }
    }
}
