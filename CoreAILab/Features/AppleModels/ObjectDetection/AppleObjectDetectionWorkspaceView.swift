import SwiftUI
import UniformTypeIdentifiers

struct AppleObjectDetectionWorkspaceView: View {
    @State private var workspace = AppleObjectDetectionWorkspaceModel()
    @State private var isImportingModel = false
    @State private var isImportingImage = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AppleObjectDetectionHeaderView(
                    modelName: workspace.modelName,
                    imageName: workspace.imageName,
                    statusMessage: workspace.statusMessage,
                    isBusy: workspace.isLoadingModel || workspace.isRunning
                )

                HStack(spacing: 12) {
                    Button("Import YOLOS Model", systemImage: "shippingbox", action: importModel)
                    Button("Choose Image", systemImage: "photo", action: importImage)
                    Button("Run Detection", systemImage: "play.fill", action: runDetection)
                        .buttonStyle(.borderedProminent)
                        .disabled(!workspace.canRun)
                }

                Text("Export command")
                    .font(.headline)
                Text("uv run models/yolo/export.py --model hustvl/yolos-tiny --dtype float16")
                    .font(.body.monospaced())
                    .textSelection(.enabled)

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
            }
            .frame(maxWidth: 1_200, alignment: .leading)
            .padding(32)
        }
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
        .alert("Object Detection Failed", isPresented: $workspace.isShowingError) {
        } message: {
            Text(workspace.errorMessage ?? "The request could not be completed.")
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
            workspace.presentImportError(error)
        }
    }

    private func handleImageImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            workspace.loadImage(from: url)
        case .failure(let error):
            workspace.presentImportError(error)
        }
    }
}
