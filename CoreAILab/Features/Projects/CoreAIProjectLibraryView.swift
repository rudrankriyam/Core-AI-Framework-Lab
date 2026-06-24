import SwiftData
import SwiftUI

struct CoreAIProjectLibraryView: View {
    @Query(sort: \LabProject.updatedAt, order: .reverse)
    private var projects: [LabProject]

    @State private var controller = CoreAIProjectLibraryController()
    @State private var path: [CoreAIProjectRoute] = []
    @State private var isCreatingProject = false
    @State private var searchText = ""

    var body: some View {
        let visibleProjects = searchText.isEmpty
            ? projects
            : projects.filter { $0.name.localizedStandardContains(searchText) }

        NavigationStack(path: $path) {
            Group {
                if projects.isEmpty {
                    ContentUnavailableView {
                        Label("Create Your First Project", systemImage: "folder.badge.plus")
                    } description: {
                        Text(
                            "Keep models, resource bundles, provenance, runs, and evidence together in checksummed storage."
                        )
                    } actions: {
                        Button(
                            "New Project",
                            systemImage: "plus",
                            action: showNewProject
                        )
                        .buttonStyle(.borderedProminent)
                    }
                } else if visibleProjects.isEmpty {
                    ContentUnavailableView.search
                } else {
                    List(visibleProjects) { project in
                        NavigationLink(value: CoreAIProjectRoute.project(project.id)) {
                            CoreAIProjectRowView(project: project)
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .searchable(text: $searchText, prompt: "Search projects")
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
