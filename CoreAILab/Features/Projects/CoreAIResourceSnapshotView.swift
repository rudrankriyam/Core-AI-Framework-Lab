import SwiftUI

struct CoreAIResourceSnapshotView: View {
    @Environment(\.dismiss) private var dismiss

    let snapshot: CoreAIResourceFolderSnapshot

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    LabeledContent("Files", value: snapshot.files.count.formatted())
                    LabeledContent(
                        "Directories",
                        value: snapshot.directories.count.formatted()
                    )
                    LabeledContent("Stored size") {
                        Text(snapshot.byteCount, format: .byteCount(style: .file))
                    }
                }

                if !snapshot.directories.isEmpty {
                    Section("Directories") {
                        ForEach(snapshot.directories, id: \.self) { relativePath in
                            Label(relativePath, systemImage: "folder")
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Files") {
                    if snapshot.files.isEmpty {
                        ContentUnavailableView(
                            "Empty Resource Folder",
                            systemImage: "folder"
                        )
                    } else {
                        ForEach(snapshot.files, id: \.relativePath) { file in
                            VStack(alignment: .leading) {
                                Label(file.relativePath, systemImage: "doc")
                                Text(file.byteCount, format: .byteCount(style: .file))
                                    .foregroundStyle(.secondary)
                                Text(file.sha256Digest)
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .textSelection(.enabled)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .navigationTitle("Resource Manifest")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}
