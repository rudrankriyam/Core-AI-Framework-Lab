import SwiftData
import SwiftUI

struct CoreAINewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""

    let controller: CoreAIProjectLibraryController
    let onCreated: (LabProject) -> Void

    var body: some View {
        @Bindable var controller = controller

        NavigationStack {
            Form {
                TextField("Project Name", text: $name)
                    .textContentType(.name)
            }
            .formStyle(.grouped)
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: createProject)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 180)
        .alert("Project Could Not Be Created", isPresented: $controller.isShowingError) {
        } message: {
            Text(controller.errorMessage ?? "Core AI Lab could not create the project.")
        }
    }

    private func createProject() {
        do {
            let project = try controller.createProject(
                named: name,
                modelContext: modelContext
            )
            onCreated(project)
            dismiss()
        } catch {
            controller.present(error)
        }
    }
}
