import CoreAI
import Foundation

enum CoreAICachePolicyChoice: String, CaseIterable, Identifiable, Sendable {
    case standard
    case persistent

    var id: Self { self }

    var title: String {
        switch self {
        case .standard:
            "Standard"
        case .persistent:
            "Persistent"
        }
    }

    var detail: String {
        switch self {
        case .standard:
            "Allows Core AI to reclaim the entry under storage pressure or when the source changes."
        case .persistent:
            "Keeps the entry when the source is removed or storage is pressured, until manual removal or OS invalidation."
        }
    }

    var policy: AIModelCache.Policy {
        switch self {
        case .standard:
            .default
        case .persistent:
            .persistent
        }
    }
}
