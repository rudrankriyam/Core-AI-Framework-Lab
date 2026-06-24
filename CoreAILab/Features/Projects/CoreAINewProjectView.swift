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
                Section {
                    TextField("Project Name", text: $name)
                        .textContentType(.name)
                } header: {
                    Label("Project", systemImage: "folder")
                } footer: {
                    Text("Projects keep related assets, provenance, runs, and evidence together.")
                }
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
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 220)
        .alert("Couldn't Create the Project", isPresented: $controller.isShowingError) {
        } message: {
            Text(controller.errorMessage ?? "Choose a different name and try again.")
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
