import Foundation

struct CoreAIDeviceFacts: Codable, Equatable, Sendable {
    let modelName: String
    let modelIdentifier: String
    let operatingSystemVersion: String
    let destinationIdentifier: String

    func validate(path: String = "device") throws {
        try CoreAIManifestValidator.requireNonempty(modelName, path: "\(path).modelName")
        try CoreAIManifestValidator.requireNonempty(
            operatingSystemVersion,
            path: "\(path).operatingSystemVersion"
        )
        try CoreAIManifestValidator.requireNonempty(
            destinationIdentifier,
            path: "\(path).destinationIdentifier"
        )
    }
}
