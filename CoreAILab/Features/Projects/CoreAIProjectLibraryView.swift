import SwiftData
import SwiftUI

struct CoreAIProjectLibraryView: View {
    @Query(sort: \LabProject.updatedAt, order: .reverse)
    private var projects: [LabProject]

    @State private var controller = CoreAIProjectLibraryController()
    @State private var path: [CoreAIProjectRoute] = []
    @State private var isCreatingProject = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if projects.isEmpty {
                    ContentUnavailableView {
                        Label("Create a Lab Project", systemImage: "folder.badge.plus")
                    } description: {
                        Text(
                            "Projects keep imported models and resource bundles available across launches with checksummed, deduplicated storage."
                        )
                    } actions: {
                        Button(
                            "New Project",
                            systemImage: "plus",
                            action: showNewProject
                        )
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(projects) { project in
                        NavigationLink(value: CoreAIProjectRoute.project(project.id)) {
                            CoreAIProjectRowView(project: project)
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(
                        "New Project",
                        systemImage: "plus",
                        action: showNewProject
                    )
                }
            }
            .navigationDestination(for: CoreAIProjectRoute.self) { route in
                CoreAIProjectDestinationView(
                    route: route,
                    projects: projects,
                    controller: controller
                )
            }
        }
        .sheet(isPresented: $isCreatingProject) {
            CoreAINewProjectView(controller: controller) { project in
                path.append(.project(project.id))
            }
        }
        .alert("Project Operation Failed", isPresented: $controller.isShowingError) {
        } message: {
            Text(controller.errorMessage ?? "The project operation failed.")
        }
    }

    private func showNewProject() {
        isCreatingProject = true
    }
}
