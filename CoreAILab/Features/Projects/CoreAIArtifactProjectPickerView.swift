import SwiftData
import SwiftUI

struct CoreAIArtifactProjectPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LabProject.updatedAt, order: .reverse)
    private var projects: [LabProject]

    @State private var controller = CoreAIProjectLibraryController()
    @State private var isCreatingProject = false

    let artifactURL: URL

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    ContentUnavailableView {
                        Label("No Projects", systemImage: "folder.badge.plus")
                    } actions: {
                        Button(
                            "New Project",
                            systemImage: "plus",
                            action: showNewProject
                        )
                    }
                } else {
                    List(projects) { project in
                        Button(action: { storeArtifact(in: project) }) {
                            CoreAIProjectRowView(project: project)
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.isPerformingOperation)
                    }
                }
            }
            .navigationTitle("Store in Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: dismiss.callAsFunction)
                }
            }
            .overlay {
                if controller.isPerformingOperation {
                    ProgressView("Hashing and storing artifact…")
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .sheet(isPresented: $isCreatingProject) {
            CoreAINewProjectView(controller: controller) { project in
                storeArtifact(in: project)
            }
        }
        .alert("Couldn't Store the Artifact", isPresented: $controller.isShowingError) {
        } message: {
            Text(controller.errorMessage ?? "Choose another project or try again.")
        }
    }

    private func showNewProject() {
        isCreatingProject = true
    }

    private func storeArtifact(in project: LabProject) {
        Task {
            do {
                try await controller.importArtifact(
                    from: artifactURL,
                    into: project,
                    modelContext: modelContext
                )
                dismiss()
            } catch {
                controller.present(error)
            }
        }
    }
}
