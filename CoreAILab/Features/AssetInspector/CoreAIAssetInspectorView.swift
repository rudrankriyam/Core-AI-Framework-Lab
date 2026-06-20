import SwiftUI

struct CoreAIAssetInspectorView: View {
    @State private var workspace = CoreAIAssetWorkspaceModel()
    @State private var isImportingModel = false
    let initialURL: URL?

    init(initialURL: URL? = nil) {
        self.initialURL = initialURL
    }

    var body: some View {
        Group {
            if let report = workspace.report {
                CoreAIAssetReportView(report: report, workspace: workspace)
            } else if workspace.isInspecting {
                ContentUnavailableView {
                    Label("Inspecting Model", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Reading metadata, functions, and compute types from the Core AI asset.")
                } actions: {
                    ProgressView()
                }
            } else {
                ContentUnavailableView {
                    Label("Inspect a Core AI Model", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Open any exported .aimodel package, including assets produced by Apple's coreai-models recipes.")
                } actions: {
                    Button("Open Model", systemImage: "folder", action: openModelPicker)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Asset Inspector")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Open Model", systemImage: "folder", action: openModelPicker)
                    .disabled(workspace.phase.isBusy)
            }
        }
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [.coreAIModelAsset, .folder]
        ) { result in
            handleModelImport(result)
        }
        .alert("Unable to Inspect Model", isPresented: $workspace.isShowingError) {
        } message: {
            Text(workspace.errorMessage ?? "The model could not be inspected.")
        }
        .task(id: initialURL) {
            if let initialURL {
                await workspace.inspect(url: initialURL)
            }
        }
    }

    private func openModelPicker() {
        isImportingModel = true
    }

    private func handleModelImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            Task {
                await workspace.inspect(url: url)
            }
        case .failure(let error):
            workspace.presentImportError(error)
        }
    }
}
