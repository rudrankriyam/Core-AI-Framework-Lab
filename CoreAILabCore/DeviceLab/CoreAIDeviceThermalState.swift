import Foundation

enum CoreAIDeviceThermalState: String, Codable, CaseIterable, Sendable {
    case unavailable
    case nominal
    case fair
    case serious
    case critical
    case unknown
}
