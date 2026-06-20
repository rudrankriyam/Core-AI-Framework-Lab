import CoreGraphics
import Foundation
import Testing
@testable import CoreAILab

@MainActor
struct AppleObjectDetectionWorkspaceModelTests {
    @Test
    func failedReplacementKeepsThePreviouslyLoadedModelAvailable() async {
        let engine = ObjectDetectorStub()
        let workspace = AppleObjectDetectionWorkspaceModel(engine: engine)
        let validURL = URL(filePath: "/tmp/valid.aimodel")
        let invalidURL = URL(filePath: "/tmp/invalid.aimodel")

        await workspace.loadModel(from: validURL)
        #expect(workspace.modelName == "valid.aimodel")

        await workspace.loadModel(from: invalidURL)

        #expect(workspace.modelName == "valid.aimodel")
        #expect(workspace.isShowingError)
    }

    @Test
    func successfulLoadClearsAnEarlierErrorAlert() async {
        let workspace = AppleObjectDetectionWorkspaceModel(engine: ObjectDetectorStub())

        await workspace.loadModel(from: URL(filePath: "/tmp/invalid.aimodel"))
        #expect(workspace.isShowingError)

        await workspace.loadModel(from: URL(filePath: "/tmp/valid.aimodel"))
        #expect(!workspace.isShowingError)
        #expect(workspace.errorMessage == nil)
    }
}

@MainActor
struct CoreAIAssetWorkspaceModelTests {
    @Test
    func failedReplacementKeepsThePreviouslyInspectedReport() async {
        let validURL = URL(filePath: "/tmp/valid.aimodel")
        let validReport = CoreAIModelAssetReport(
            url: validURL,
            isValid: true,
            author: "Core AI Lab",
            license: "Test",
            description: "Fixture",
            functionNames: ["main"],
            computeTypes: ["float16"]
        )
        let workspace = CoreAIAssetWorkspaceModel(
            inspectionService: CoreAIAssetInspectorStub(report: validReport),
            specializationService: CoreAISpecializationServiceStub()
        )

        await workspace.inspect(url: validURL)
        #expect(workspace.report == validReport)

        await workspace.inspect(url: URL(filePath: "/tmp/invalid.aimodel"))
        #expect(workspace.report == validReport)
        #expect(workspace.isShowingError)

        await workspace.inspect(url: validURL)
        #expect(!workspace.isShowingError)
    }
}

private actor ObjectDetectorStub: AppleObjectDetecting {
    func loadModel(at url: URL) async throws {
        if url.lastPathComponent == "invalid.aimodel" {
            throw ObjectDetectorStubError.invalidModel
        }
    }

    func detect(in image: CGImage) async throws -> [AppleObjectDetection] {
        []
    }
}

private enum ObjectDetectorStubError: LocalizedError {
    case invalidModel

    var errorDescription: String? {
        "The replacement model is invalid."
    }
}

private actor CoreAIAssetInspectorStub: CoreAIAssetInspecting {
    let report: CoreAIModelAssetReport

    init(report: CoreAIModelAssetReport) {
        self.report = report
    }

    func inspect(url: URL) async throws -> CoreAIModelAssetReport {
        guard url == report.url else {
            throw CoreAIAssetInspectorStubError.invalidModel
        }
        return report
    }
}

private enum CoreAIAssetInspectorStubError: LocalizedError {
    case invalidModel

    var errorDescription: String? {
        "The replacement model is invalid."
    }
}
