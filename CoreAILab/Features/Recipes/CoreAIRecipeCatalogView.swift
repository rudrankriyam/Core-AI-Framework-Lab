import SwiftUI
import UniformTypeIdentifiers

struct CoreAIRecipeCatalogView: View {
    @State private var model = CoreAIRecipeCatalogWorkspaceModel()
    @State private var isChoosingBundle = false

    var body: some View {
        @Bindable var model = model
        let entries = model.entries

        NavigationStack {
            List {
                Section {
                    Text("Trust describes where a recipe came from. Verification describes which checks have evidence. Neither state grants imported code permission to run.")
                        .foregroundStyle(.secondary)
                }

                Section("Curated recipes") {
                    if let catalogError = model.catalogError {
                        ContentUnavailableView(
                            "Catalog Unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(catalogError)
                        )
                    } else if entries.isEmpty {
                        ContentUnavailableView(
                            "No Curated Recipes",
                            systemImage: "books.vertical"
                        )
                    } else {
                        ForEach(entries) { entry in
                            CoreAIRecipeCatalogEntryView(entry: entry)
                        }
                    }
                }

                Section("Imported bundle") {
                    CoreAIImportedRecipeBundleView(
                        summary: model.importedSummary,
                        codeApprovalState: model.codeApprovalState,
                        isImporting: model.phase == .importing,
                        statusMessage: model.statusMessage,
                        onApprove: approveReferencedCode,
                        onRevoke: revokeReferencedCode
                    )
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(
                        "Import Bundle",
                        systemImage: "square.and.arrow.down",
                        action: chooseBundle
                    )
                    .disabled(model.phase == .importing)
                }
            }
            .fileImporter(
                isPresented: $isChoosingBundle,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .alert(
                "Recipe Bundle Import Failed",
                isPresented: $model.isShowingError,
                presenting: model.errorMessage
            ) { _ in
            } message: { message in
                Text(message)
            }
        }
    }

    private func chooseBundle() {
        isChoosingBundle = true
    }

    private func handleImportResult(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await model.importBundle(at: url) }
        case .failure(let error):
            model.presentImportError(error)
        }
    }

    private func approveReferencedCode() {
        Task { await model.approveReferencedCodeExecution() }
    }

    private func revokeReferencedCode() {
        Task { await model.revokeReferencedCodeExecutionApproval() }
    }
}
