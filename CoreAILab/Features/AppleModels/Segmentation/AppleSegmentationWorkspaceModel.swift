import CoreGraphics
import Foundation
import ImageIO
import Observation

@MainActor
@Observable
final class AppleSegmentationWorkspaceModel {
    let example: AppleSegmentationExample
    private(set) var modelName: String?
    private(set) var sourceImage: CGImage?
    private(set) var renderedImage: CGImage?
    private(set) var imageName: String?
    private(set) var result: AppleSegmentationResult?
    private(set) var statusMessage: String
    private(set) var isLoadingModel = false
    private(set) var isRunning = false
    private(set) var errorMessage: String?
    var textPrompt = "cat"
    var pointX = 0.0
    var pointY = 0.0
    var isShowingError = false

    @ObservationIgnored
    private let engine: any AppleImageSegmenting

    init(
        example: AppleSegmentationExample,
        engine: any AppleImageSegmenting = AppleImageSegmenterEngine()
    ) {
        self.example = example
        self.engine = engine
        statusMessage = example.modelImportDescription
    }

    var isBusy: Bool {
        isLoadingModel || isRunning
    }

    var canRun: Bool {
        guard modelName != nil, sourceImage != nil, !isBusy else { return false }
        return !example.usesTextPrompt || !normalizedTextPrompt.isEmpty
    }

    var imageWidth: Double {
        Double(sourceImage?.width ?? 1)
    }

    var imageHeight: Double {
        Double(sourceImage?.height ?? 1)
    }

    var previewImage: CGImage? {
        renderedImage ?? sourceImage
    }

    func loadModel(from url: URL) async {
        guard !isBusy else { return }
        isLoadingModel = true
        statusMessage = "Specializing and loading \(url.lastPathComponent)…"
        defer { isLoadingModel = false }

        do {
            try await engine.loadModel(at: url)
            modelName = url.lastPathComponent
            clearResult()
            clearError()
            statusMessage = sourceImage == nil
                ? "Model ready. Choose an image to continue."
                : "Model and image ready."
        } catch {
            present(error)
        }
    }

    func loadImage(from url: URL) {
        guard !isBusy else { return }
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            present(AppleSegmentationError.unreadableImage)
            return
        }

        sourceImage = image
        renderedImage = nil
        imageName = url.lastPathComponent
        result = nil
        pointX = Double(image.width) / 2
        pointY = Double(image.height) / 2
        clearError()
        statusMessage = modelName == nil
            ? "Image ready. Import the \(example.title) bundle to continue."
            : "Model and image ready."
    }

    func runSegmentation() async {
        guard modelName != nil else {
            present(AppleSegmentationError.modelNotLoaded)
            return
        }
        guard let sourceImage else {
            present(AppleSegmentationError.imageNotLoaded)
            return
        }

        let query: AppleSegmentationQuery
        if example.usesTextPrompt {
            guard !normalizedTextPrompt.isEmpty else {
                present(AppleSegmentationError.emptyTextPrompt)
                return
            }
            query = .text(normalizedTextPrompt)
        } else {
            query = .point(x: Float(pointX), y: Float(pointY))
        }

        isRunning = true
        statusMessage = "Running \(example.title) with Core AI…"
        defer { isRunning = false }

        do {
            let response = try await engine.segment(image: sourceImage, query: query)
            result = response
            renderedImage = response.renderedImage
            clearError()
            statusMessage = response.segmentCount == 1
                ? "Rendered 1 segment."
                : "Rendered \(response.segmentCount) segments."
        } catch {
            present(error)
        }
    }

    func presentImportError(_ error: any Error) {
        present(error)
    }

    private var normalizedTextPrompt: String {
        textPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearResult() {
        result = nil
        renderedImage = nil
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        statusMessage = error.localizedDescription
        isShowingError = true
    }

    private func clearError() {
        errorMessage = nil
        isShowingError = false
    }
}
