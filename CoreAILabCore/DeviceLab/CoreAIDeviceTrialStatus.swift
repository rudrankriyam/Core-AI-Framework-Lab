import Foundation

enum CoreAIDeviceTrialStatus: String, Codable, CaseIterable, Sendable {
    case notRun
    case succeeded
    case failed
}
