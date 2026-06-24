import SwiftUI

struct CoreAIProjectRowView: View {
    let project: LabProject

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(project.name, systemImage: "folder.fill")
                .font(.headline)

            Spacer()

            Text("^[\(project.artifactLinks.count) artifact](inflect: true)")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(project.name), \(project.artifactLinks.count) artifacts, \(project.storedByteCount.formatted(.byteCount(style: .file)))"
        )
        .help(
            "\(project.storedByteCount.formatted(.byteCount(style: .file))) · Updated \(project.updatedAt.formatted(.relative(presentation: .named)))"
        )
    }
}
