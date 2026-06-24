import SwiftUI
import UniformTypeIdentifiers

struct CoreAIRecipeCatalogView: View {
    @State private var model = CoreAIRecipeCatalogWorkspaceModel()
    @State private var isChoosingBundle = false

    var body: some View {
        @Bindable var model = model
        let entries = model.entries

        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Label("Trust & Verification", systemImage: "checkmark.shield")
                            .font(.headline)
                        Text("Trust describes a recipe's source. Verification names the checks backed by evidence. Neither state grants imported code permission to run.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
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
                } header: {
                    Label("Curated Recipes", systemImage: "checkmark.seal")
                }

                Section {
                    CoreAIImportedRecipeBundleView(
                        summary: model.importedSummary,
                        codeApprovalState: model.codeApprovalState,
                        isImporting: model.phase == .importing,
                        statusMessage: model.statusMessage,
                        onApprove: approveReferencedCode,
                        onRevoke: revokeReferencedCode
                    )
                } header: {
                    Label("Imported Bundle", systemImage: "shippingbox.and.arrow.backward")
                }
            }
            .formStyle(.grouped)
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
                "Couldn't Import the Recipe Bundle",
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
            if (error as? CocoaError)?.code != .userCancelled {
                model.presentImportError(error)
            }
        }
    }

    private func approveReferencedCode() {
        Task { await model.approveReferencedCodeExecution() }
    }

    private func revokeReferencedCode() {
        Task { await model.revokeReferencedCodeExecutionApproval() }
    }
}
