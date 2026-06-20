import SwiftUI

struct CoreAIProjectRowView: View {
    let project: LabProject

    var body: some View {
        HStack {
            Label(project.name, systemImage: "folder")

            Spacer()

            VStack(alignment: .trailing) {
                Text(project.artifactLinks.count, format: .number)
                    .monospacedDigit()
                Text(
                    project.storedByteCount,
                    format: .byteCount(style: .file)
                )
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(project.name), \(project.artifactLinks.count) artifacts, \(project.storedByteCount.formatted(.byteCount(style: .file)))"
        )
    }
}
