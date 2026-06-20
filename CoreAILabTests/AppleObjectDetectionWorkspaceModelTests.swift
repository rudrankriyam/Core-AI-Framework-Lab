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
