import SwiftUI

struct CoreAIProjectResourceSummaryView: View {
    let artifact: ModelArtifactRecord
    let browse: () -> Void

    var body: some View {
        Section("Resource Folder") {
            LabeledContent("Files", value: artifact.fileCount.formatted())
            LabeledContent("Stored size") {
                Text(artifact.byteCount, format: .byteCount(style: .file))
            }
            Button(
                "Browse File Manifest",
                systemImage: "list.bullet.rectangle",
                action: browse
            )
        }
    }
}
