import SwiftUI

struct CoreAIProjectDestinationView: View {
    let route: CoreAIProjectRoute
    let projects: [LabProject]
    let controller: CoreAIProjectLibraryController

    var body: some View {
        switch route {
        case .project(let projectID):
            if let project = project(withID: projectID) {
                CoreAIProjectDetailView(
                    project: project,
                    controller: controller
                )
            } else {
                ContentUnavailableView(
                    "Project Unavailable",
                    systemImage: "folder.badge.questionmark",
                    description: Text("The project may have been deleted in another window.")
                )
            }
        case .artifact(let linkID):
            if let link = artifactLink(withID: linkID) {
                CoreAIProjectArtifactDetailView(
                    link: link,
                    controller: controller
                )
            } else {
                ContentUnavailableView(
                    "Artifact Unavailable",
                    systemImage: "shippingbox",
                    description: Text("The project no longer contains this artifact.")
                )
            }
        case .inspect(let linkID):
            if let link = artifactLink(withID: linkID),
               let artifact = link.artifact,
               let storedURL = try? controller.validatedStoredURL(for: artifact) {
                CoreAIAssetInspectorView(
                    initialURL: storedURL,
                    projectArtifactLink: link,
                    projectController: controller
                )
            } else {
                ContentUnavailableView("Artifact Unavailable", systemImage: "shippingbox")
            }
        case .workbench(let linkID):
            if let link = artifactLink(withID: linkID),
               let artifact = link.artifact,
               let storedURL = try? controller.validatedStoredURL(for: artifact) {
                CoreAIFunctionWorkbenchView(
                    initialURL: storedURL,
                    projectArtifactLink: link,
                    projectController: controller
                )
            } else {
                ContentUnavailableView("Artifact Unavailable", systemImage: "shippingbox")
            }
        }
    }

    private func project(withID id: UUID) -> LabProject? {
        projects.first { $0.id == id }
    }

    private func artifactLink(withID id: UUID) -> ProjectArtifactLink? {
        projects.lazy
            .flatMap(\.artifactLinks)
            .first { $0.id == id }
    }
}
