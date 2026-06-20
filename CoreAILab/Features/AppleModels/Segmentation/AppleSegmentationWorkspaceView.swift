import SwiftUI
import UniformTypeIdentifiers

struct AppleSegmentationWorkspaceView: View {
    @State private var workspace: AppleSegmentationWorkspaceModel
    @State private var isImportingModel = false
    @State private var isImportingImage = false
    private let initialModelURL: URL?

    init(
        example: AppleSegmentationExample,
        initialModelURL: URL? = nil
    ) {
        _workspace = State(initialValue: AppleSegmentationWorkspaceModel(example: example))
        self.initialModelURL = initialModelURL
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Model", value: workspace.modelName ?? "Not loaded")
                LabeledContent("Image", value: workspace.imageName ?? "Not loaded")
                Label(
                    workspace.statusMessage,
                    systemImage: statusSystemImage
                )
                    .foregroundStyle(workspace.isBusy ? .primary : .secondary)
            } header: {
                Label(workspace.example.title, systemImage: "square.stack.3d.up")
            }

            Section("Run Apple's Export") {
                HStack {
                    Button("Import Model Bundle", systemImage: "shippingbox", action: importModel)
                    Button("Choose Image", systemImage: "photo", action: importImage)
                    Button("Run Segmentation", systemImage: "play.fill", action: runSegmentation)
                        .buttonStyle(.borderedProminent)
                        .disabled(!workspace.canRun)
                }
                .disabled(workspace.isBusy)

                Text(workspace.example.exportCommand)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }

            AppleSegmentationQueryControlsView(workspace: workspace)
            AppleSegmentationPreviewView(
                image: workspace.previewImage,
                result: workspace.result
            )
        }
        .formStyle(.grouped)
        .navigationTitle("\(workspace.example.title) Segmentation")
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [.folder]
        ) { result in
            handleModelImport(result)
        }
        .fileImporter(
            isPresented: $isImportingImage,
            allowedContentTypes: [.image]
        ) { result in
            handleImageImport(result)
        }
        .alert("Segmentation Failed", isPresented: $workspace.isShowingError) {
        } message: {
            Text(workspace.errorMessage ?? "The request could not be completed.")
        }
        .task(id: initialModelURL) {
            if let initialModelURL {
                await workspace.loadModel(from: initialModelURL)
            }
        }
    }

    private func importModel() {
        isImportingModel = true
    }

    private var statusSystemImage: String {
        if workspace.isBusy {
            return "hourglass"
        }
        if workspace.isShowingError {
            return "exclamationmark.triangle"
        }
        if workspace.modelName != nil, workspace.sourceImage != nil {
            return "checkmark.circle"
        }
        return "info.circle"
    }

    private func importImage() {
        isImportingImage = true
    }

    private func runSegmentation() {
        Task {
            await workspace.runSegmentation()
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
