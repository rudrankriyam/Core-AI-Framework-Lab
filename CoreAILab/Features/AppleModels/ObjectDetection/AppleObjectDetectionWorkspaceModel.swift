import CoreGraphics
import Foundation
import ImageIO
import Observation

@MainActor
@Observable
final class AppleObjectDetectionWorkspaceModel {
    let runCoordinator: CoreAIRunLifecycleCoordinator
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
    private let engine: any AppleObjectDetecting
    @ObservationIgnored
    let runContext: CoreAIRuntimeRunContext
    @ObservationIgnored
    private var activeRunID: UUID?

    init(
        engine: any AppleObjectDetecting = AppleObjectDetectorEngine(),
        runContext: CoreAIRuntimeRunContext? = nil,
        runCoordinator: CoreAIRunLifecycleCoordinator? = nil
    ) {
        self.engine = engine
        self.runContext = runContext ?? .workspaceDefault(
            experienceID: "apple-yolos-tiny-detection",
            title: "YOLOS Tiny",
            modelIdentifier: "yolos-tiny"
        )
        self.runCoordinator = runCoordinator ?? CoreAIRunLifecycleCoordinator()
    }

    var isBusy: Bool {
        isLoadingModel || isRunning
    }

    var canRun: Bool {
        modelName != nil && sourceImage != nil && !isBusy
    }

    func loadModel(from url: URL) async {
        guard !isBusy else { return }
        isLoadingModel = true
        statusMessage = "Specializing and loading \(url.lastPathComponent)…"
        defer { isLoadingModel = false }

        do {
            try CoreAIRuntimeArtifactValidator.validate(
                url,
                for: .appleObjectDetection,
                context: runContext
            )
            try await engine.loadModel(at: url)
            modelName = url.lastPathComponent
            runCoordinator.modelDidLoad(
                context: runContext,
                modelIdentity: url.lastPathComponent
            )
            detections = []
            clearError()
            statusMessage = "Model ready. Choose an image to run object detection."
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
            present(AppleObjectDetectionError.unreadableImage)
            return
        }

        sourceImage = image
        imageName = url.lastPathComponent
        detections = []
        clearError()
        statusMessage = modelName == nil
            ? "Image ready. Import a YOLOS model to continue."
            : "Image and model ready."
    }

    func runDetection() async {
        guard !isBusy, activeRunID == nil else { return }
        guard modelName != nil else {
            present(AppleObjectDetectionError.modelNotLoaded)
            return
        }
        guard let sourceImage else {
            present(AppleObjectDetectionError.imageNotLoaded)
            return
        }

        detections = []
        let runID = UUID()
        activeRunID = runID
        isRunning = true
        statusMessage = "Running YOLOS with Core AI…"
        defer {
            if activeRunID == runID {
                activeRunID = nil
                isRunning = false
            }
        }
        let runToken = runCoordinator.start(
            context: runContext,
            modelIdentity: modelName ?? runContext.comparisonIdentity.modelIdentifier
        )

        do {
            let detectedObjects = try await engine.detect(in: sourceImage)
            try Task.checkCancellation()
            guard activeRunID == runID else {
                runCoordinator.cancel(
                    runToken,
                    summary: "Object detection superseded by a newer request."
                )
                return
            }
            detections = detectedObjects
            clearError()
            statusMessage = detections.isEmpty
                ? "No objects met the default confidence threshold."
                : detections.count == 1
                    ? "Found 1 object."
                    : "Found \(detections.count) objects."
            runCoordinator.succeed(runToken, summary: statusMessage)
        } catch is CancellationError {
            guard activeRunID == runID else {
                runCoordinator.cancel(
                    runToken,
                    summary: "Object detection superseded by a newer request."
                )
                return
            }
            statusMessage = "Object detection canceled."
            runCoordinator.cancel(runToken, summary: statusMessage)
        } catch {
            guard activeRunID == runID else {
                runCoordinator.cancel(
                    runToken,
                    summary: "Object detection superseded by a newer request."
                )
                return
            }
            runCoordinator.fail(runToken, error: error)
            present(error)
        }
    }

    func presentImportError(_ error: any Error) {
        guard !isBusy else { return }
        present(error)
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
