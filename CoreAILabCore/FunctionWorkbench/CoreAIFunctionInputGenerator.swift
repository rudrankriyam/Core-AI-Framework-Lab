import Foundation

enum CoreAIFunctionInputGenerator: String, CaseIterable, Identifiable, Sendable {
    case zeros
    case random

    var id: Self { self }

    var title: String {
        switch self {
        case .zeros:
            "Zeros"
        case .random:
            "Seeded random"
        }
    }
}
