import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CoreAIProjectDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isImportingArtifact = false
    @State private var isRenamingProject = false
    @State private var isConfirmingProjectDeletion = false
    @State private var proposedName = ""

    let project: LabProject
    let controller: CoreAIProjectLibraryController

    var body: some View {
        @Bindable var controller = controller

        Form {
            Section {
                LabeledContent("Artifacts", value: project.artifactLinks.count.formatted())
                LabeledContent("Stored size") {
                    Text(project.storedByteCount, format: .byteCount(style: .file))
                }
                LabeledContent("Created") {
                    Text(project.createdAt, format: .dateTime.day().month().year().hour().minute())
                }
                LabeledContent("Last opened") {
                    Text(project.lastOpenedAt, format: .relative(presentation: .named))
                }
            } header: {
                Label("Overview", systemImage: "folder")
            }

            Section {
                if project.artifactLinks.isEmpty {
                    ContentUnavailableView {
                        Label("No Stored Artifacts", systemImage: "shippingbox")
                    } description: {
                        Text(
                            "Import a .aimodel package, an Apple resource folder, or a supporting model file."
                        )
                    } actions: {
                        Button(
                            "Import Artifact",
                            systemImage: "square.and.arrow.down",
                            action: showArtifactImporter
                        )
                    }
                } else {
                    ForEach(project.sortedArtifactLinks) { link in
                        NavigationLink(value: CoreAIProjectRoute.artifact(link.id)) {
                            CoreAIProjectArtifactRowView(link: link)
                        }
                    }
                }

                if controller.activeProjectID == project.id {
                    ProgressView(controller.activeOperation?.title ?? "Updating project…")
                        .accessibilityAddTraits(.updatesFrequently)
                }
            } header: {
                Label("Artifacts", systemImage: "shippingbox")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(
                    "Import Artifact",
                    systemImage: "square.and.arrow.down",
                    action: showArtifactImporter
                )
                .disabled(controller.isPerformingOperation)

                Menu("Project Actions", systemImage: "ellipsis.circle") {
                    Button("Rename Project", systemImage: "pencil", action: showRenamePrompt)
                    Button(
                        "Delete Project",
                        systemImage: "trash",
                        role: .destructive,
                        action: confirmProjectDeletion
                    )
                }
                .disabled(controller.isPerformingOperation)
            }
        }
        .fileImporter(
            isPresented: $isImportingArtifact,
            allowedContentTypes: [.item]
        ) { result in
            handleArtifactImport(result)
        }
        .alert("Rename Project", isPresented: $isRenamingProject) {
            TextField("Project Name", text: $proposedName)
            Button("Cancel", role: .cancel) {}
            Button("Rename", action: renameProject)
                .disabled(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Project metadata updates immediately; stored model content is unchanged.")
        }
        .alert("Delete \(project.name)?", isPresented: $isConfirmingProjectDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Project", role: .destructive, action: deleteProject)
        } message: {
            Text(
                "Project metadata is deleted. Stored artifacts are reclaimed only when no other project references the same SHA-256 content."
            )
        }
        .alert("Couldn't Update the Project", isPresented: $controller.isShowingError) {
        } message: {
            Text(controller.errorMessage ?? "Check the project and try again.")
        }
        .task(id: project.id) {
            do {
                try controller.markOpened(project, modelContext: modelContext)
            } catch {
                controller.present(error)
            }
        }
    }

    private func showArtifactImporter() {
        isImportingArtifact = true
    }

    private func handleArtifactImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            Task {
                do {
                    try await controller.importArtifact(
                        from: url,
                        into: project,
                        modelContext: modelContext
                    )
                } catch {
                    controller.present(error)
                }
            }
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                controller.present(error)
            }
        }
    }

    private func showRenamePrompt() {
        proposedName = project.name
        isRenamingProject = true
    }

    private func renameProject() {
        do {
            try controller.renameProject(
                project,
                to: proposedName,
                modelContext: modelContext
            )
        } catch {
            controller.present(error)
        }
    }

    private func confirmProjectDeletion() {
        isConfirmingProjectDeletion = true
    }

    private func deleteProject() {
        Task {
            do {
                try await controller.deleteProject(project, modelContext: modelContext)
                dismiss()
            } catch {
                controller.present(error)
            }
        }
    }
}
