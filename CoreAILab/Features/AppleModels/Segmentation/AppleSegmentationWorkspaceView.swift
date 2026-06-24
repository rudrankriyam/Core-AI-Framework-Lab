import SwiftUI
import UniformTypeIdentifiers

struct AppleSegmentationWorkspaceView: View {
    @State private var workspace: AppleSegmentationWorkspaceModel
    @State private var isImportingModel = false
    @State private var isImportingImage = false
    private let initialModelURL: URL?

    init(
        example: AppleSegmentationExample,
        initialModelURL: URL? = nil,
        runContext: CoreAIRuntimeRunContext? = nil,
        runCoordinator: CoreAIRunLifecycleCoordinator? = nil
    ) {
        _workspace = State(
            initialValue: AppleSegmentationWorkspaceModel(
                example: example,
                runContext: runContext,
                runCoordinator: runCoordinator
            )
        )
        self.initialModelURL = initialModelURL
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Model", value: workspace.modelName ?? "Not loaded")
                LabeledContent("Image", value: workspace.imageName ?? "Not loaded")
                if workspace.isBusy {
                    ProgressView(workspace.statusMessage)
                        .accessibilityAddTraits(.updatesFrequently)
                } else {
                    Label(workspace.statusMessage, systemImage: statusSystemImage)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label(workspace.example.title, systemImage: "square.stack.3d.up")
            }

            CoreAIRuntimeLifecycleView(
                coordinator: workspace.runCoordinator,
                context: workspace.runContext
            )

            Section {
                ViewThatFits(in: .horizontal) {
                    inputActions(axis: .horizontal)
                    inputActions(axis: .vertical)
                }
                .disabled(workspace.isBusy)
            } header: {
                Label("Model & Image", systemImage: "square.stack.3d.up")
            }

            Section {
                Text(workspace.example.exportCommand)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            } header: {
                Label("Apple Export Command", systemImage: "terminal")
            }

            AppleSegmentationQueryControlsView(workspace: workspace)
            AppleSegmentationPreviewView(
                image: workspace.previewImage,
                result: workspace.result
            )
        }
        .formStyle(.grouped)
        .navigationTitle("\(workspace.example.title) Segmentation")
        .toolbar {
#if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Button("Run Segmentation", systemImage: "play.fill", action: runSegmentation)
                    .disabled(!workspace.canRun)
                    .help(workspace.statusMessage)
            }
#endif
        }
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
        .alert("Couldn't Segment the Image", isPresented: $workspace.isShowingError) {
        } message: {
            Text(workspace.errorMessage ?? "Check the model bundle and image, then try again.")
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
            ? AnyLayout(HStackLayout())
            : AnyLayout(VStackLayout(alignment: .leading))

        return layout {
            Button("Import Model Bundle", systemImage: "shippingbox", action: importModel)
            Button("Choose Image", systemImage: "photo", action: importImage)
#if !os(macOS)
            Button("Run Segmentation", systemImage: "play.fill", action: runSegmentation)
                .buttonStyle(.borderedProminent)
                .disabled(!workspace.canRun)
#endif
        }
    }

    private func presentSelectionError(_ error: any Error) {
        if (error as? CocoaError)?.code != .userCancelled {
            workspace.presentImportError(error)
        }
    }
}
