import Foundation

enum CoreAISourceProvenanceKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case localFile
    case download
    case modelRegistry
    case sourceRepository
    case generated
    case unknown

    var id: Self { self }

    var title: String {
        switch self {
        case .localFile:
            "Local file"
        case .download:
            "Downloaded artifact"
        case .modelRegistry:
            "Model registry"
        case .sourceRepository:
            "Source repository"
        case .generated:
            "Generated locally"
        case .unknown:
            "Unknown"
        }
    }
}
