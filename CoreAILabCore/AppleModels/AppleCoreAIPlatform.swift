import Foundation

enum AppleCoreAIPlatform: String, Codable, Hashable, Sendable {
    case iOS
    case macOS

    static var current: AppleCoreAIPlatform {
        #if os(macOS)
        .macOS
        #else
        .iOS
        #endif
    }
}
