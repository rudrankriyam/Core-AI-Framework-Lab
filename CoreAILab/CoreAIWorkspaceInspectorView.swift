import SwiftUI

struct CoreAIWorkspaceInspectorView: View {
    let section: CoreAILabSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                inspectorSection(
                    "Workflow",
                    systemImage: "point.3.connected.trianglepath.dotted"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(section.workflowSteps.indices, id: \.self) { index in
                            inspectorLabel(
                                section.workflowSteps[index],
                                systemImage: "\(index + 1).circle"
                            )
                        }
                    }
                }

                Divider()
                    .padding(.leading, contentInset)

                inspectorSection("Evidence", systemImage: "checkmark.seal") {
                    Text(section.evidenceBoundary)
                        .padding(.leading, contentInset)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .navigationTitle("Workspace")
        .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
    }

    private let contentInset: CGFloat = 24

    private func inspectorSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorLabel(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorLabel(
        _ title: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 16)
            Text(title)
        }
    }
}

#Preview {
    CoreAIWorkspaceInspectorView(section: .runtime)
}
