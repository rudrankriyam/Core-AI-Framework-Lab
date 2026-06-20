import SwiftData
import SwiftUI

struct CoreAIProjectArtifactDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingRemoval = false

    let link: ProjectArtifactLink
    let controller: CoreAIProjectLibraryController

    var body: some View {
        @Bindable var controller = controller

        Form {
            if let artifact = link.artifact {
                Section("Artifact") {
                    LabeledContent("Name", value: link.displayName)
                    LabeledContent("Kind", value: artifact.kind.title)
                    LabeledContent("Size") {
                        Text(artifact.byteCount, format: .byteCount(style: .file))
                    }
                    LabeledContent("Files", value: artifact.fileCount.formatted())
                    LabeledContent("Imported") {
                        Text(artifact.importedAt, format: .dateTime.day().month().year().hour().minute())
                    }
                }

                Section("Integrity") {
                    LabeledContent("SHA-256") {
                        Text(artifact.sha256Digest)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Store path") {
                        Text(artifact.storageRelativePath)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if artifact.kind == .modelAsset {
                    Section("Open With") {
                        NavigationLink(
                            "Asset Inspector",
                            value: CoreAIProjectRoute.inspect(link.id)
                        )
                        NavigationLink(
                            "Function Workbench",
                            value: CoreAIProjectRoute.workbench(link.id)
                        )
                    }
                }

                #if os(macOS)
                Section {
                    Button(
                        "Reveal Stored Copy in Finder",
                        systemImage: "folder",
                        action: revealInFinder
                    )
                }
                #endif
            } else {
                ContentUnavailableView("Artifact Unavailable", systemImage: "shippingbox")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(link.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(
                    "Remove from Project",
                    systemImage: "trash",
                    role: .destructive,
                    action: confirmRemoval
                )
                .disabled(controller.isImporting)
            }
        }
        .alert("Remove \(link.displayName)?", isPresented: $isConfirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive, action: removeArtifact)
        } message: {
            Text(
                "The stored copy is reclaimed only if no other project references the same content."
            )
        }
        .alert("Artifact Operation Failed", isPresented: $controller.isShowingError) {
        } message: {
            Text(controller.errorMessage ?? "The artifact operation failed.")
        }
    }

    private func confirmRemoval() {
        isConfirmingRemoval = true
    }

    private func removeArtifact() {
        Task {
            do {
                try await controller.removeArtifactLink(link, modelContext: modelContext)
                dismiss()
            } catch {
                controller.present(error)
            }
        }
    }

    #if os(macOS)
    private func revealInFinder() {
        guard let artifact = link.artifact else { return }
        NSWorkspace.shared.activateFileViewerSelecting([
            controller.storedURL(for: artifact)
        ])
    }
    #endif
}
