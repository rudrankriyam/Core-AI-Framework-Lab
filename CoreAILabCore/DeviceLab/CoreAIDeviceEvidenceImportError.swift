import Foundation

enum CoreAIDeviceEvidenceImportError: Error, Equatable, LocalizedError {
    case notARegularFile
    case emptyFile
    case fileTooLarge(found: UInt64, maximum: UInt64)

    var errorDescription: String? {
        switch self {
        case .notARegularFile:
            "Device evidence must be a regular JSON file."
        case .emptyFile:
            "Device evidence must not be empty."
        case .fileTooLarge(let found, let maximum):
            "Device evidence is \(found) bytes; the import limit is \(maximum) bytes."
        }
    }
}
