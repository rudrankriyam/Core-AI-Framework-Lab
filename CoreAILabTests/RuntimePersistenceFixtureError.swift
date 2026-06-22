import Foundation

enum RuntimePersistenceFixtureError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Fixture runtime failed."
    }
}
