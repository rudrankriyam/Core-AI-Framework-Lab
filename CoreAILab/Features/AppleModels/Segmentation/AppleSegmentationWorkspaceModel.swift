import CoreGraphics
import Foundation
import ImageIO
import Observation

@MainActor
@Observable
final class AppleSegmentationWorkspaceModel {
    let example: AppleSegmentationExample
    let runCoordinator: CoreAIRunLifecycleCoordinator
    private(set) var modelName: String?
    private(set) var sourceImage: CGImage?
    private(set) var renderedImage: CGImage?
    private(set) var imageName: String?
    private(set) var result: AppleSegmentationResult?
    private(set) var statusMessage: String
    private(set) var isLoadingModel = false
    private(set) var isRunning = false
    private(set) var errorMessage: String?
    private var storedTextPrompt = "cat"
    private var storedPointX = 0.0
    private var storedPointY = 0.0
    var isShowingError = false

    @ObservationIgnored
    private let engine: any AppleImageSegmenting
    @ObservationIgnored
    let runContext: CoreAIRuntimeRunContext
    @ObservationIgnored
    private var activeRunID: UUID?

    init(
        example: AppleSegmentationExample,
        engine: any AppleImageSegmenting = AppleImageSegmenterEngine(),
        runContext: CoreAIRuntimeRunContext? = nil,
        runCoordinator: CoreAIRunLifecycleCoordinator? = nil
    ) {
        self.example = example
        self.engine = engine
        self.runContext = runContext ?? .workspaceDefault(
            experienceID: "apple-segmentation-\(example.rawValue)",
            title: example.title,
            modelIdentifier: example.rawValue
        )
        self.runCoordinator = runCoordinator ?? CoreAIRunLifecycleCoordinator()
        statusMessage = example.modelImportDescription
    }

    var isBusy: Bool {
        isLoadingModel || isRunning
    }

    var textPrompt: String {
        get { storedTextPrompt }
        set {
            guard !isBusy else { return }
            storedTextPrompt = newValue
        }
    }

    var pointX: Double {
        get { storedPointX }
        set {
            guard !isBusy else { return }
            storedPointX = newValue
        }
    }

    var pointY: Double {
        get { storedPointY }
        set {
            guard !isBusy else { return }
            storedPointY = newValue
        }
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
            try CoreAIRuntimeArtifactValidator.validate(
                url,
                for: .appleSegmentation,
                context: runContext
            )
            try await engine.loadModel(at: url)
            modelName = url.lastPathComponent
            runCoordinator.modelDidLoad(
                context: runContext,
                modelIdentity: url.lastPathComponent
            )
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
        guard !isBusy, activeRunID == nil else { return }
        guard modelName != nil else {
            present(AppleSegmentationError.modelNotLoaded)
            return
        }
        guard let sourceImage else {
            present(AppleSegmentationError.imageNotLoaded)
            return
        }

        clearResult()

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

        let runID = UUID()
        activeRunID = runID
        isRunning = true
        statusMessage = "Running \(example.title) with Core AI…"
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
            let response = try await engine.segment(image: sourceImage, query: query)
            try Task.checkCancellation()
            guard activeRunID == runID else {
                runCoordinator.cancel(
                    runToken,
                    summary: "Segmentation superseded by a newer request."
                )
                return
            }
            result = response
            renderedImage = response.renderedImage
            clearError()
            statusMessage = response.segmentCount == 1
                ? "Rendered 1 segment."
                : "Rendered \(response.segmentCount) segments."
            runCoordinator.succeed(runToken, summary: statusMessage)
        } catch is CancellationError {
            guard activeRunID == runID else {
                runCoordinator.cancel(
                    runToken,
                    summary: "Segmentation superseded by a newer request."
                )
                return
            }
            statusMessage = "Segmentation canceled."
            runCoordinator.cancel(runToken, summary: statusMessage)
        } catch {
            guard activeRunID == runID else {
                runCoordinator.cancel(
                    runToken,
                    summary: "Segmentation superseded by a newer request."
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
