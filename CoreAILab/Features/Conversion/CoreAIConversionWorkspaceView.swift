import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
struct CoreAIConversionWorkspaceView: View {
    @State private var workspace: CoreAIConversionWorkspaceModel
    @State private var isChoosingRepository = false
    @State private var isChoosingOutputDirectory = false
    @State private var isChoosingUVExecutable = false
    @State private var artifactToStore: CoreAIConversionArtifact?

    init(initialModelID: String? = nil) {
        _workspace = State(
            initialValue: CoreAIConversionWorkspaceModel(initialModelID: initialModelID)
        )
    }

    var body: some View {
        Group {
            if let catalogError = workspace.catalogError {
                ContentUnavailableView(
                    "Catalog Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(catalogError)
                )
            } else {
                HSplitView {
                    CoreAIConversionSetupView(
                        workspace: workspace,
                        chooseRepository: chooseRepository,
                        chooseOutputDirectory: chooseOutputDirectory,
                        chooseUVExecutable: chooseUVExecutable
                    )
                    .frame(minWidth: 360, idealWidth: 440)

                    CoreAIConversionEvidenceView(
                        workspace: workspace,
                        revealInFinder: revealInFinder,
                        storeInProject: chooseProject
                    )
                    .frame(minWidth: 420, idealWidth: 620)
                }
            }
        }
        .navigationTitle("Convert")
        .navigationDestination(for: CoreAIConversionArtifact.self) { artifact in
            CoreAIConversionArtifactDestinationView(artifact: artifact)
        }
        .fileImporter(
            isPresented: $isChoosingRepository,
            allowedContentTypes: [.folder]
        ) { result in
            handleRepositorySelection(result)
        }
        .fileImporter(
            isPresented: $isChoosingOutputDirectory,
            allowedContentTypes: [.folder]
        ) { result in
            handleOutputSelection(result)
        }
        .fileImporter(
            isPresented: $isChoosingUVExecutable,
            allowedContentTypes: [.item]
        ) { result in
            handleUVSelection(result)
        }
        .alert("Conversion Error", isPresented: $workspace.isShowingError) {
        } message: {
            Text(workspace.errorMessage ?? "The conversion could not be completed.")
        }
        .sheet(item: $artifactToStore) { artifact in
            CoreAIArtifactProjectPickerView(artifactURL: artifact.url)
        }
        .task {
            await workspace.refreshEnvironment()
        }
        .onDisappear {
            workspace.cancelConversion()
        }
    }

    private func chooseRepository() {
        isChoosingRepository = true
    }

    private func chooseOutputDirectory() {
        isChoosingOutputDirectory = true
    }

    private func chooseUVExecutable() {
        isChoosingUVExecutable = true
    }

    private func handleRepositorySelection(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            workspace.selectRepository(url)
            Task {
                await workspace.refreshEnvironment()
            }
        case .failure(let error):
            workspace.presentImportError(error)
        }
    }

    private func handleOutputSelection(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            workspace.selectOutputDirectory(url)
            Task {
                await workspace.refreshEnvironment()
            }
        case .failure(let error):
            workspace.presentImportError(error)
        }
    }

    private func handleUVSelection(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            workspace.selectUVExecutable(url)
            Task {
                await workspace.refreshEnvironment()
            }
        case .failure(let error):
            workspace.presentImportError(error)
        }
    }

    private func revealInFinder(_ artifact: CoreAIConversionArtifact) {
        NSWorkspace.shared.activateFileViewerSelecting([artifact.url])
    }

    private func chooseProject(for artifact: CoreAIConversionArtifact) {
        artifactToStore = artifact
    }
}
#else
struct CoreAIConversionWorkspaceView: View {
    init(initialModelID: String? = nil) {}

    var body: some View {
        ContentUnavailableView(
            "Conversion Requires a Mac",
            systemImage: "desktopcomputer",
            description: Text(
                "Core AI authoring uses Xcode, Python, PyTorch, and local command-line tools. Convert on macOS, then bring the resulting asset to this device."
            )
        )
        .navigationTitle("Convert")
    }
}
#endif
