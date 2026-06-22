import Foundation

enum CoreAIAssetDeliveryMode: String, Codable, CaseIterable, Sendable {
    case appDownload
    case onDemand

    var title: String {
        switch self {
        case .appDownload:
            "App download"
        case .onDemand:
            "On demand"
        }
    }
}
