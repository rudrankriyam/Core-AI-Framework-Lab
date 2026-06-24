import SwiftData
import SwiftUI

struct CoreAIAssetInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var workspace = CoreAIAssetWorkspaceModel()
    @State private var isImportingModel = false
    let initialURL: URL?
    let projectArtifactLink: ProjectArtifactLink?
    let projectController: CoreAIProjectLibraryController?

    init(
        initialURL: URL? = nil,
        projectArtifactLink: ProjectArtifactLink? = nil,
        projectController: CoreAIProjectLibraryController? = nil
    ) {
        self.initialURL = initialURL
        self.projectArtifactLink = projectArtifactLink
        self.projectController = projectController
    }

    var body: some View {
        Group {
            if let report = workspace.report {
                CoreAIAssetReportView(
                    report: report,
                    workspace: workspace,
                    allowsCacheRemoval: projectArtifactLink == nil
                )
            } else if workspace.isInspecting {
                ContentUnavailableView {
                    Label("Inspecting Model", systemImage: "doc.text.magnifyingglass")
                } actions: {
                    ProgressView()
                }
            } else {
                ContentUnavailableView {
                    Label("Inspect a Core AI Model", systemImage: "doc.text.magnifyingglass")
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
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [.coreAIModelAsset, .folder]
        ) { result in
            handleModelImport(result)
        }
        .alert("Couldn't Inspect the Model", isPresented: $workspace.isShowingError) {
        } message: {
            Text(workspace.errorMessage ?? "Check the model asset and try again.")
        }
        .task(id: initialURL) {
            do {
                if let initialURL = try resolvedInitialURL() {
                    await workspace.inspect(url: initialURL)
                }
            } catch {
                workspace.presentImportError(error)
            }
        }
        .onChange(of: workspace.report) { _, report in
            persistDescriptorSnapshot(report)
        }
        .onChange(of: workspace.specializationResult) { _, result in
            Task {
                await persistSpecialization(result)
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
            if (error as? CocoaError)?.code != .userCancelled {
                workspace.presentImportError(error)
            }
        }
    }

    private func persistDescriptorSnapshot(_ report: CoreAIModelAssetReport?) {
        guard let report,
              let projectArtifactLink,
              let projectController,
              isProjectArtifact(report.url) else { return }
        do {
            try projectController.recordDescriptorSnapshot(
                report,
                for: projectArtifactLink,
                modelContext: modelContext
            )
        } catch {
            workspace.presentImportError(error)
        }
    }

    private func persistSpecialization(
        _ result: CoreAISpecializationResult?
    ) async {
        guard let result,
              let sourceURL = workspace.report?.url,
              let projectArtifactLink,
              let projectController,
              isProjectArtifact(sourceURL) else { return }
        do {
            try await projectController.recordSpecializationCache(
                result,
                sourceURL: sourceURL,
                for: projectArtifactLink,
                modelContext: modelContext
            )
        } catch {
            workspace.presentImportError(error)
        }
    }

    private func isProjectArtifact(_ url: URL) -> Bool {
        guard let artifact = projectArtifactLink?.artifact,
              let projectController,
              let storedURL = try? projectController.validatedStoredURL(for: artifact) else {
            return false
        }
        return url.standardizedFileURL
            == storedURL.standardizedFileURL
    }

    private func resolvedInitialURL() throws -> URL? {
        guard let artifact = projectArtifactLink?.artifact,
              let projectController else {
            return initialURL
        }
        return try projectController.validatedStoredURL(for: artifact)
    }
}
