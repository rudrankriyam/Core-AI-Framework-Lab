import SwiftUI

struct CoreAIProjectRowView: View {
    let project: LabProject

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(project.name)
                    .font(.headline)

                HStack {
                    Label {
                        Text("^[\(project.artifactLinks.count) artifact](inflect: true)")
                    } icon: {
                        Image(systemName: "shippingbox")
                    }

                    Label {
                        Text(project.storedByteCount, format: .byteCount(style: .file))
                    } icon: {
                        Image(systemName: "internaldrive")
                    }

                    Label {
                        Text(project.updatedAt, format: .relative(presentation: .named))
                    } icon: {
                        Image(systemName: "clock")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(.tint)
        }
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(project.name), \(project.artifactLinks.count) artifacts, \(project.storedByteCount.formatted(.byteCount(style: .file)))"
        )
    }
}
