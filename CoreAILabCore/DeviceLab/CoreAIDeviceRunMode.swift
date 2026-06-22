import Foundation

enum CoreAIDeviceRunMode: String, Codable, CaseIterable, Sendable {
    case dryRun
    case physical
}
