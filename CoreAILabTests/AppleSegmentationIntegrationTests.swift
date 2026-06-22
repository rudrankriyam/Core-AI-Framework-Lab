import Foundation
import ImageIO
import Testing
@testable import CoreAILab

struct AppleSegmentationIntegrationTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["COREAI_EFFICIENT_SAM_BUNDLE_PATH"] != nil
                && ProcessInfo.processInfo.environment["COREAI_SEGMENTATION_IMAGE_PATH"] != nil,
            "Requires COREAI_EFFICIENT_SAM_BUNDLE_PATH and COREAI_SEGMENTATION_IMAGE_PATH."
        )
    )
    func exportedEfficientSAMRunsThroughAppleRuntime() async throws {
        let environment = ProcessInfo.processInfo.environment
        let modelPath = try #require(environment["COREAI_EFFICIENT_SAM_BUNDLE_PATH"])
        let imagePath = try #require(environment["COREAI_SEGMENTATION_IMAGE_PATH"])

        let image = try loadImage(at: imagePath)
        let engine = AppleImageSegmenterEngine()
        try await engine.loadModel(at: URL(filePath: modelPath))
        let result = try await engine.segment(
            image: image,
            query: .point(x: Float(image.width) / 2, y: Float(image.height) / 2)
        )

        #expect(result.renderedImage.width == image.width)
        #expect(result.renderedImage.height == image.height)
        #expect(result.segmentCount > 0)
        #expect(!result.scores.isEmpty)
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["COREAI_SAM3_BUNDLE_PATH"] != nil
                && ProcessInfo.processInfo.environment["COREAI_SEGMENTATION_IMAGE_PATH"] != nil,
            "Requires COREAI_SAM3_BUNDLE_PATH and COREAI_SEGMENTATION_IMAGE_PATH."
        )
    )
    func exportedSAM3RunsThroughAppleRuntime() async throws {
        let environment = ProcessInfo.processInfo.environment
        let modelPath = try #require(environment["COREAI_SAM3_BUNDLE_PATH"])
        let imagePath = try #require(environment["COREAI_SEGMENTATION_IMAGE_PATH"])

        let image = try loadImage(at: imagePath)
        let engine = AppleImageSegmenterEngine()
        try await engine.loadModel(at: URL(filePath: modelPath))
        let result = try await engine.segment(image: image, query: .text("cat"))

        #expect(result.renderedImage.width == image.width)
        #expect(result.renderedImage.height == image.height)
        #expect(result.segmentCount > 0)
        #expect(!result.scores.isEmpty)
    }

    private func loadImage(at path: String) throws -> CGImage {
        let source = try #require(
            CGImageSourceCreateWithURL(URL(filePath: path) as CFURL, nil)
        )
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
}
