import CoreGraphics
import Foundation
import ImageIO
import Observation

@MainActor
@Observable
final class AppleObjectDetectionWorkspaceModel {
    private(set) var modelName: String?
    private(set) var sourceImage: CGImage?
    private(set) var imageName: String?
    private(set) var detections: [AppleObjectDetection] = []
    private(set) var statusMessage = "Export YOLOS Tiny, then import its .aimodel package."
    private(set) var isLoadingModel = false
    private(set) var isRunning = false
    private(set) var errorMessage: String?
    var isShowingError = false

    @ObservationIgnored
    private let engine = AppleObjectDetectorEngine()

    var canRun: Bool {
        modelName != nil && sourceImage != nil && !isLoadingModel && !isRunning
    }

    func loadModel(from url: URL) async {
        isLoadingModel = true
        statusMessage = "Specializing and loading \(url.lastPathComponent)…"
        defer { isLoadingModel = false }

        do {
            try await engine.loadModel(at: url)
            modelName = url.lastPathComponent
            detections = []
            errorMessage = nil
            statusMessage = "Model ready. Choose an image to run object detection."
        } catch {
            modelName = nil
            present(error)
        }
    }

    func loadImage(from url: URL) {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            present(AppleObjectDetectionError.unreadableImage)
            return
        }

        sourceImage = image
        imageName = url.lastPathComponent
        detections = []
        errorMessage = nil
        statusMessage = modelName == nil
            ? "Image ready. Import a YOLOS model to continue."
            : "Image and model ready."
    }

    func runDetection() async {
        guard modelName != nil else {
            present(AppleObjectDetectionError.modelNotLoaded)
            return
        }
        guard let sourceImage else {
            present(AppleObjectDetectionError.imageNotLoaded)
            return
        }

        isRunning = true
        statusMessage = "Running YOLOS with Core AI…"
        defer { isRunning = false }

        do {
            detections = try await engine.detect(in: sourceImage)
            errorMessage = nil
            statusMessage = detections.isEmpty
                ? "No objects met the default confidence threshold."
                : detections.count == 1
                    ? "Found 1 object."
                    : "Found \(detections.count) objects."
        } catch {
            present(error)
        }
    }

    func presentImportError(_ error: any Error) {
        present(error)
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        statusMessage = error.localizedDescription
        isShowingError = true
    }
}
