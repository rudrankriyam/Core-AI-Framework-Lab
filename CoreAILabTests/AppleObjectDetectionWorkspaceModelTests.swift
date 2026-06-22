import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CoreAILab

@MainActor
struct AppleObjectDetectionWorkspaceModelTests {
    @Test
    func detectionUsesTheSharedVisionRunLifecycle() async throws {
        let workspace = AppleObjectDetectionWorkspaceModel(engine: ObjectDetectorStub())
        let imageURL = try makeTestImage()
        defer { try? FileManager.default.removeItem(at: imageURL) }
        await workspace.loadModel(from: URL(filePath: "/tmp/valid.aimodel"))
        workspace.loadImage(from: imageURL)

        await workspace.runDetection()

        #expect(workspace.runCoordinator.history.first?.state == .succeeded)
        #expect(workspace.runCoordinator.history.first?.timingClass == .cold)
    }

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

    @Test
    func delayedDetectionRejectsOverlappingRunsAndImageReplacement() async throws {
        let engine = DelayedObjectDetectorStub()
        let workspace = AppleObjectDetectionWorkspaceModel(engine: engine)
        let firstImageURL = try makeTestImage(width: 2)
        let secondImageURL = try makeTestImage(width: 3)
        defer {
            try? FileManager.default.removeItem(at: firstImageURL)
            try? FileManager.default.removeItem(at: secondImageURL)
        }
        await workspace.loadModel(from: URL(filePath: "/tmp/valid.aimodel"))
        workspace.loadImage(from: firstImageURL)

        let firstRun = Task { await workspace.runDetection() }
        await engine.waitUntilDetectionStarts()
        workspace.loadImage(from: secondImageURL)
        await workspace.runDetection()
        await engine.resumeDetection()
        await firstRun.value

        #expect(workspace.imageName == firstImageURL.lastPathComponent)
        #expect(workspace.detections.map(\.label) == ["width-2"])
        #expect(await engine.detectionCount == 1)
        #expect(workspace.runCoordinator.history.count == 1)
        #expect(workspace.runCoordinator.history.first?.timingClass == .cold)

        await workspace.runDetection()

        #expect(await engine.detectionCount == 2)
        #expect(workspace.runCoordinator.history.count == 2)
        #expect(workspace.runCoordinator.history.first?.timingClass == .warm)
    }

    private func makeTestImage(width: Int = 2) throws -> URL {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory
            .appending(path: "runtime-vision-\(UUID().uuidString).png")
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }
}

private actor DelayedObjectDetectorStub: AppleObjectDetecting {
    private var continuation: CheckedContinuation<Void, Never>?
    private var shouldDelay = true
    private(set) var detectionCount = 0

    func loadModel(at _: URL) {}

    func detect(in image: CGImage) async -> [AppleObjectDetection] {
        detectionCount += 1
        if shouldDelay {
            shouldDelay = false
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        return [
            AppleObjectDetection(
                id: 0,
                boundingBox: .zero,
                label: "width-\(image.width)",
                confidence: 1
            )
        ]
    }

    func waitUntilDetectionStarts() async {
        while detectionCount == 0 || continuation == nil {
            await Task.yield()
        }
    }

    func resumeDetection() {
        continuation?.resume()
        continuation = nil
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
