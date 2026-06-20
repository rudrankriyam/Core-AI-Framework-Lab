import Foundation
import ImageIO
import Testing
@testable import CoreAILab

struct AppleObjectDetectionIntegrationTests {
    @Test
    func exportedYOLOSModelRunsThroughAppleRuntime() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let modelPath = environment["COREAI_YOLOS_MODEL_PATH"],
              let imagePath = environment["COREAI_YOLOS_IMAGE_PATH"] else {
            return
        }

        let modelURL = URL(filePath: modelPath)
        let report = try CoreAIModelAssetInspector.inspect(url: modelURL)
        #expect(report.functionNames.contains("main"))

        let imageURL = URL(filePath: imagePath)
        let source = try #require(CGImageSourceCreateWithURL(imageURL as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        let engine = AppleObjectDetectorEngine()
        try await engine.loadModel(at: modelURL)
        let detections = try await engine.detect(in: image)

        #expect(!detections.isEmpty)
        #expect(detections.contains { $0.confidence > 0.9 })
    }
}
