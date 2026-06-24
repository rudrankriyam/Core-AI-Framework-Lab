import SwiftData
import SwiftUI

struct CoreAISourceProvenanceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var kind: CoreAISourceProvenanceKind
    @State private var sourceLocation: String
    @State private var providerName: String
    @State private var licenseName: String
    @State private var notes: String
    @State private var errorMessage: String?
    @State private var isShowingError = false

    let link: ProjectArtifactLink
    let controller: CoreAIProjectLibraryController

    init(
        link: ProjectArtifactLink,
        controller: CoreAIProjectLibraryController
    ) {
        self.link = link
        self.controller = controller
        let provenance = link.provenance
        _kind = State(initialValue: provenance?.kind ?? .unknown)
        _sourceLocation = State(initialValue: provenance?.sourceLocation ?? "")
        _providerName = State(initialValue: provenance?.providerName ?? "")
        _licenseName = State(initialValue: provenance?.licenseName ?? "")
        _notes = State(initialValue: provenance?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Source type", selection: $kind) {
                        ForEach(CoreAISourceProvenanceKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }

                    TextField("Source location", text: $sourceLocation, axis: .vertical)
                        .lineLimit(2...5)
                        .help("Record enough detail to trace the artifact to its source and license.")
                    TextField("Provider", text: $providerName)
                    TextField("License", text: $licenseName)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Label("Source", systemImage: "link")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Source Provenance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(kind != .unknown && sourceLocation.trimmed.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .alert("Couldn't Save Provenance", isPresented: $isShowingError) {
                Button("Dismiss", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Check the source details and try again.")
            }
        }
    }

    private func save() {
        do {
            try controller.updateSourceProvenance(
                for: link,
                kind: kind,
                sourceLocation: sourceLocation,
                providerName: providerName,
                licenseName: licenseName,
                notes: notes,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
