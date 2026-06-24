import SwiftUI
import UniformTypeIdentifiers

struct AppleObjectDetectionWorkspaceView: View {
    @State private var workspace: AppleObjectDetectionWorkspaceModel
    @State private var isImportingModel = false
    @State private var isImportingImage = false

    init(
        runContext: CoreAIRuntimeRunContext? = nil,
        runCoordinator: CoreAIRunLifecycleCoordinator? = nil
    ) {
        _workspace = State(
            initialValue: AppleObjectDetectionWorkspaceModel(
                runContext: runContext,
                runCoordinator: runCoordinator
            )
        )
    }

    var body: some View {
        Form {
            Section {
                AppleObjectDetectionHeaderView(
                    modelName: workspace.modelName,
                    imageName: workspace.imageName,
                    statusMessage: workspace.statusMessage,
                    isBusy: workspace.isLoadingModel || workspace.isRunning
                )
            }

            Section {
                ViewThatFits(in: .horizontal) {
                    inputActions(axis: .horizontal)
                    inputActions(axis: .vertical)
                }
                .disabled(workspace.isBusy)
            } header: {
                Label("Model & Image", systemImage: "viewfinder")
            }

            CoreAIRuntimeLifecycleView(
                coordinator: workspace.runCoordinator,
                context: workspace.runContext
            )

            Section {
                Text("uv run models/yolo/export.py --model hustvl/yolos-tiny --dtype float16")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            } header: {
                Label("Apple Export Command", systemImage: "terminal")
            }

            Section {
                if let sourceImage = workspace.sourceImage {
                    AppleObjectDetectionPreviewView(
                        image: sourceImage,
                        detections: workspace.detections
                    )
                } else {
                    ContentUnavailableView(
                        "Choose an Image",
                        systemImage: "photo",
                        description: Text("The result will show Apple's COCO labels, confidence, and bounding boxes.")
                    )
                }
            } header: {
                Label("Result", systemImage: "viewfinder")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Object Detection")
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [.coreAIModelAsset, .folder]
        ) { result in
            handleModelImport(result)
        }
        .fileImporter(
            isPresented: $isImportingImage,
            allowedContentTypes: [.image]
        ) { result in
            handleImageImport(result)
        }
        .alert("Couldn't Detect Objects", isPresented: $workspace.isShowingError) {
        } message: {
            Text(workspace.errorMessage ?? "Check the model and image, then try again.")
        }
    }

    private func importModel() {
        isImportingModel = true
    }

    private func importImage() {
        isImportingImage = true
    }

    private func runDetection() {
        Task {
            await workspace.runDetection()
        }
    }

    private func handleModelImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            Task {
                await workspace.loadModel(from: url)
            }
        case .failure(let error):
            presentSelectionError(error)
        }
    }

    private func handleImageImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            workspace.loadImage(from: url)
        case .failure(let error):
            presentSelectionError(error)
        }
    }

    private func inputActions(axis: Axis) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(alignment: .leading))

        return layout {
            Button("Import YOLOS Model", systemImage: "shippingbox", action: importModel)
            Button("Choose Image", systemImage: "photo", action: importImage)
            Button("Run Detection", systemImage: "play.fill", action: runDetection)
                .buttonStyle(.borderedProminent)
                .disabled(!workspace.canRun)
        }
    }

    private func presentSelectionError(_ error: any Error) {
        if (error as? CocoaError)?.code != .userCancelled {
            workspace.presentImportError(error)
        }
    }
}
