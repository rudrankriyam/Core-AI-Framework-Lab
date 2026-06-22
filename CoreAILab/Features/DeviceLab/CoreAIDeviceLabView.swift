import SwiftUI
import UniformTypeIdentifiers

struct CoreAIDeviceLabView: View {
    @State private var workspace = CoreAIDeviceLabWorkspaceModel()
    @State private var isImportingEvidence = false

    var body: some View {
        Form {
            Section {
                Text(
                    "Author an iPhone target, plan its asset delivery, and import evidence from the physical runner. Preferences remain separate from measured execution placement."
                )
                .foregroundStyle(.secondary)
            }

            CoreAIDeviceTargetAuthoringView(workspace: workspace)
            CoreAIDeviceStoragePlanView(workspace: workspace)
            CoreAIDeviceDiagnosticsView(diagnostics: workspace.diagnostics)
            CoreAIDeviceEvidenceView(
                workspace: workspace,
                isImportingEvidence: $isImportingEvidence
            )
        }
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
