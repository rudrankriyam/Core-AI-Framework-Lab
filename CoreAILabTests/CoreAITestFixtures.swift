import Foundation

enum CoreAITestFixtureError: LocalizedError {
    case missingTensorModel
    case incompleteTensorModel([String])

    var errorDescription: String? {
        switch self {
        case .missingTensorModel:
            "CoreAILabTensorFixture.aimodel is missing from the test bundle."
        case .incompleteTensorModel(let files):
            "CoreAILabTensorFixture.aimodel is missing: \(files.joined(separator: ", "))."
        }
    }
}

enum CoreAITestFixtures {
    static func tensorModelURL() throws -> URL {
        let bundle = Bundle(for: CoreAITestBundleToken.self)
        guard let modelURL = bundle.url(
            forResource: "CoreAILabTensorFixture",
            withExtension: "aimodel",
            subdirectory: "Fixtures"
        ) else {
            throw CoreAITestFixtureError.missingTensorModel
        }

        let requiredFiles = ["main.hash", "main.mlirb", "metadata.json"]
        let missingFiles = requiredFiles.filter {
            !FileManager.default.fileExists(
                atPath: modelURL.appending(path: $0).path
            )
        }
        guard missingFiles.isEmpty else {
            throw CoreAITestFixtureError.incompleteTensorModel(missingFiles)
        }
        return modelURL
    }
}

private final class CoreAITestBundleToken {}
