import SwiftUI
import UniformTypeIdentifiers

struct CoreAIDeviceLabView: View {
    @State private var workspace = CoreAIDeviceLabWorkspaceModel()
    @State private var isImportingEvidence = false

    var body: some View {
        Form {
            CoreAIDeviceTargetAuthoringView(workspace: workspace)
            CoreAIDeviceStoragePlanView(workspace: workspace)
            CoreAIDeviceDiagnosticsView(diagnostics: workspace.diagnostics)
            CoreAIDeviceEvidenceView(
                workspace: workspace,
                isImportingEvidence: $isImportingEvidence
            )
        }
        .formStyle(.grouped)
        .help(
            "Author an iPhone target, plan asset delivery, and import physical-runner evidence."
        )
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
            if (error as? CocoaError)?.code != .userCancelled {
                workspace.reportImportFailure(error)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CoreAIDeviceLabView()
    }
}
