import SwiftData
import SwiftUI

struct CoreAIProjectArtifactDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingRemoval = false
    @State private var isShowingProvenanceEditor = false
    @State private var isShowingResourceManifest = false
    @State private var isConfirmingCacheRemoval = false
    @State private var pendingCacheRecordID: UUID?

    let link: ProjectArtifactLink
    let controller: CoreAIProjectLibraryController

    var body: some View {
        @Bindable var controller = controller

        Form {
            if let artifact = link.artifact {
                Section {
                    LabeledContent("Name", value: link.displayName)
                    LabeledContent(
                        "Kind",
                        value: artifact.kind?.title ?? "Unsupported"
                    )
                    LabeledContent("Size") {
                        Text(artifact.byteCount, format: .byteCount(style: .file))
                    }
                    LabeledContent("Files", value: artifact.fileCount.formatted())
                    LabeledContent("Imported") {
                        Text(artifact.importedAt, format: .dateTime.day().month().year().hour().minute())
                    }
                } header: {
                    Label("Artifact", systemImage: "shippingbox")
                }

                Section {
                    LabeledContent("SHA-256") {
                        Text(artifact.sha256Digest)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Store path") {
                        Text(artifact.storageRelativePath)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                } header: {
                    Label("Integrity", systemImage: "checkmark.seal")
                }

                if artifact.resourceSnapshotData != nil {
                    CoreAIProjectResourceSummaryView(
                        artifact: artifact,
                        browse: showResourceManifest
                    )
                }

                CoreAISourceProvenanceSummaryView(
                    provenance: link.provenance,
                    edit: showProvenanceEditor
                )

                if let snapshot = try? artifact.decodedDescriptorSnapshot() {
                    CoreAIProjectDescriptorSnapshotView(
                        snapshot: snapshot,
                        inspectedAt: artifact.descriptorInspectedAt
                    )
                } else if artifact.descriptorSnapshotData != nil {
                    Section("Model Descriptor") {
                        Label(
                            "The persisted descriptor snapshot is invalid.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.secondary)
                    }
                }

                if artifact.kind == .modelAsset {
                    Section {
                        NavigationLink(value: CoreAIProjectRoute.inspect(link.id)) {
                            Label("Asset Inspector", systemImage: "doc.text.magnifyingglass")
                        }
                        NavigationLink(value: CoreAIProjectRoute.workbench(link.id)) {
                            Label("Function Workbench", systemImage: "function")
                        }
                    } header: {
                        Label("Open With", systemImage: "arrow.up.forward.app")
                    }

                    CoreAIProjectSpecializationCacheView(
                        link: link,
                        isInteractionDisabled: controller.isPerformingOperation,
                        isUpdatingCache: controller.activeOperation
                            == .managingSpecializationCache,
                        remove: confirmCacheRemoval,
                        removeAll: confirmAllCacheRemoval
                    )
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
                .disabled(controller.isPerformingOperation)
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
        .confirmationDialog(
            pendingCacheRecordID == nil
                ? "Remove all cached configurations?"
                : "Remove this cached configuration?",
            isPresented: $isConfirmingCacheRemoval,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel, action: cancelCacheRemoval)
            Button(
                pendingCacheRecordID == nil
                    ? "Remove All Configurations"
                    : "Remove Configuration",
                role: .destructive,
                action: removePreparedCache
            )
        } message: {
            Text(
                "Project cache records are removed. Core AI deletes configurations only when another project does not still reference them."
            )
        }
        .alert("Couldn't Update the Artifact", isPresented: $controller.isShowingError) {
        } message: {
            Text(controller.errorMessage ?? "Check the stored artifact and try again.")
        }
        .sheet(isPresented: $isShowingProvenanceEditor) {
            CoreAISourceProvenanceEditorView(
                link: link,
                controller: controller
            )
        }
        .sheet(isPresented: $isShowingResourceManifest) {
            if let artifact = link.artifact,
               let snapshot = try? artifact.decodedResourceSnapshot() {
                CoreAIResourceSnapshotView(snapshot: snapshot)
            } else {
                ContentUnavailableView(
                    "Resource Manifest Unavailable",
                    systemImage: "folder.badge.questionmark"
                )
            }
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

    private func showProvenanceEditor() {
        isShowingProvenanceEditor = true
    }

    private func showResourceManifest() {
        isShowingResourceManifest = true
    }

    private func confirmCacheRemoval(_ record: CoreAISpecializationCacheRecord) {
        pendingCacheRecordID = record.id
        isConfirmingCacheRemoval = true
    }

    private func confirmAllCacheRemoval() {
        pendingCacheRecordID = nil
        isConfirmingCacheRemoval = true
    }

    private func cancelCacheRemoval() {
        pendingCacheRecordID = nil
        isConfirmingCacheRemoval = false
    }

    private func removePreparedCache() {
        let recordID = pendingCacheRecordID
        cancelCacheRemoval()
        Task {
            do {
                if let recordID {
                    guard let record = link.specializationCaches.first(where: {
                        $0.id == recordID
                    }) else {
                        throw CoreAIProjectLibraryError.invalidSpecializationCacheRecord
                    }
                    try await controller.removeSpecializationCache(
                        record,
                        modelContext: modelContext
                    )
                } else {
                    try await controller.removeAllSpecializationCaches(
                        for: link,
                        modelContext: modelContext
                    )
                }
            } catch {
                controller.present(error)
            }
        }
    }

    #if os(macOS)
    private func revealInFinder() {
        guard let artifact = link.artifact,
              let storedURL = try? controller.validatedStoredURL(for: artifact) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([
            storedURL
        ])
    }
    #endif
}
