import SwiftUI
import UniformTypeIdentifiers

struct CoreAIDeviceLabView: View {
    @State private var workspace = CoreAIDeviceLabWorkspaceModel()
    @State private var isImportingEvidence = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(
                        "Author an iPhone target, plan asset delivery, and import evidence from the physical runner. Preferences remain separate from measured execution placement."
                    )
                    .foregroundStyle(.secondary)
                } label: {
                    Label("Physical Device Planning", systemImage: "iphone.gen3")
                        .font(.headline)
                }
            }

            CoreAIDeviceTargetAuthoringView(workspace: workspace)
            CoreAIDeviceStoragePlanView(workspace: workspace)
            CoreAIDeviceDiagnosticsView(diagnostics: workspace.diagnostics)
            CoreAIDeviceEvidenceView(
                workspace: workspace,
                isImportingEvidence: $isImportingEvidence
            )
        }
        .formStyle(.grouped)
        .navigationTitle("Device Lab")
        .fileImporter(
            isPresented: $isImportingEvidence,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleEvidenceImport
        )
    }

    private func handleEvidenceImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            workspace.importEvidence(from: url)
        case .failure(let error):
            workspace.reportImportFailure(error)
        }
    }
}

#Preview {
    NavigationStack {
        CoreAIDeviceLabView()
    }
}
