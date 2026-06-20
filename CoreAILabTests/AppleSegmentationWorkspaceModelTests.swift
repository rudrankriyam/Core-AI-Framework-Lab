import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CoreAILab

@MainActor
struct AppleSegmentationWorkspaceModelTests {
    @Test
    func catalogModelsMapToTheirRunnableExamples() throws {
        #expect(AppleSegmentationExample(shortName: "efficient-sam-vitt") == .efficientSAM)
        #expect(AppleSegmentationExample(shortName: "sam3") == .sam3)
        #expect(AppleSegmentationExample(shortName: "yolos-tiny") == nil)
    }

    @Test
    func efficientSAMRunsTheSelectedPoint() async throws {
        let engine = AppleImageSegmenterStub()
        let workspace = AppleSegmentationWorkspaceModel(
            example: .efficientSAM,
            engine: engine
        )
        let imageURL = try makeTestImage(width: 8, height: 6)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        await workspace.loadModel(from: URL(filePath: "/tmp/efficient-sam"))
        workspace.loadImage(from: imageURL)
        workspace.pointX = 3
        workspace.pointY = 2
        await workspace.runSegmentation()

        #expect(await engine.queries == [.point(x: 3, y: 2)])
        #expect(workspace.result?.segmentCount == 1)
        #expect(workspace.statusMessage == "Rendered 1 segment.")
    }

    @Test
    func sam3RunsANormalizedTextPrompt() async throws {
        let engine = AppleImageSegmenterStub()
        let workspace = AppleSegmentationWorkspaceModel(example: .sam3, engine: engine)
        let imageURL = try makeTestImage(width: 4, height: 4)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        await workspace.loadModel(from: URL(filePath: "/tmp/sam3"))
        workspace.loadImage(from: imageURL)
        workspace.textPrompt = "  bicycle  "
        await workspace.runSegmentation()

        #expect(await engine.queries == [.text("bicycle")])
        #expect(workspace.result?.scores == [0.9])
    }

    @Test
    func failedReplacementPreservesTheRunnableSegmenter() async throws {
        let engine = AppleImageSegmenterStub()
        let workspace = AppleSegmentationWorkspaceModel(
            example: .efficientSAM,
            engine: engine
        )
        let imageURL = try makeTestImage(width: 4, height: 4)
        defer { try? FileManager.default.removeItem(at: imageURL) }
        await workspace.loadModel(from: URL(filePath: "/tmp/valid-bundle"))
        workspace.loadImage(from: imageURL)
        await workspace.loadModel(from: URL(filePath: "/tmp/invalid-bundle"))
        #expect(workspace.isShowingError)
        await workspace.runSegmentation()

        #expect(workspace.modelName == "valid-bundle")
        #expect(!workspace.isShowingError)
        #expect(await engine.queries.count == 1)
        #expect(workspace.result?.segmentCount == 1)
    }

    private func makeTestImage(width: Int, height: Int) throws -> URL {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )
        )
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory
            .appending(path: "core-ai-segmentation-\(UUID().uuidString).png")
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }
}

private actor AppleImageSegmenterStub: AppleImageSegmenting {
    private(set) var queries: [AppleSegmentationQuery] = []

    func loadModel(at url: URL) throws {
        if url.lastPathComponent == "invalid-bundle" {
            throw AppleImageSegmenterStubError.invalidModel
        }
    }

    func segment(
        image: CGImage,
        query: AppleSegmentationQuery
    ) -> AppleSegmentationResult {
        queries.append(query)
        return AppleSegmentationResult(
            renderedImage: image,
            segmentCount: 1,
            scores: [0.9]
        )
    }
}

private enum AppleImageSegmenterStubError: LocalizedError {
    case invalidModel

    var errorDescription: String? {
        "The replacement segmenter bundle is invalid."
    }
}
