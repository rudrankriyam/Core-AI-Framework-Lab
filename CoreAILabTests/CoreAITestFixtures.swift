import Foundation

enum CoreAITestFixtureError: LocalizedError {
    case missingTensorModel
    case incompleteTensorModel([String])
    case missingDiarizationFeatures
    case missingDeviceLabEvidence

    var errorDescription: String? {
        switch self {
        case .missingTensorModel:
            "CoreAILabTensorFixture.aimodel is missing from the test bundle."
        case .incompleteTensorModel(let files):
            "CoreAILabTensorFixture.aimodel is missing: \(files.joined(separator: ", "))."
        case .missingDiarizationFeatures:
            "CAMPPlusKaldiFeatures.float32 is missing from the test bundle."
        case .missingDeviceLabEvidence:
            "DeviceLabDryRunEvidence.json is missing from the test bundle."
        }
    }
}

enum CoreAITestFixtures {
    static func deviceLabDryRunEvidenceData() throws -> Data {
        let bundle = Bundle(for: CoreAITestBundleToken.self)
        guard let url = bundle.url(
            forResource: "DeviceLabDryRunEvidence",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw CoreAITestFixtureError.missingDeviceLabEvidence
        }
        return try Data(contentsOf: url)
    }

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

    static func diarizationFeatureURL() throws -> URL {
        let bundle = Bundle(for: CoreAITestBundleToken.self)
        guard let url = bundle.url(
            forResource: "CAMPPlusKaldiFeatures",
            withExtension: "float32",
            subdirectory: "Fixtures/Diarization"
        ) else {
            throw CoreAITestFixtureError.missingDiarizationFeatures
        }
        return url
    }
}

private final class CoreAITestBundleToken {}
