import SwiftUI

struct CoreAIWorkspaceInspectorView: View {
    let section: CoreAILabSection

    var body: some View {
        Form {
            Section {
                LabeledContent("Area", value: section.areaTitle)
                Text(section.summary)
                    .foregroundStyle(.secondary)
            } header: {
                Label(section.title, systemImage: section.systemImage)
            }

            Section {
                ForEach(section.workflowSteps.indices, id: \.self) { index in
                    Label(
                        section.workflowSteps[index],
                        systemImage: "\(index + 1).circle"
                    )
                }
            } header: {
                Label("Workflow", systemImage: "point.3.connected.trianglepath.dotted")
            }

            Section {
                Text(section.evidenceBoundary)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Evidence Boundary", systemImage: "checkmark.seal")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Workspace")
        .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
    }
}

#Preview {
    CoreAIWorkspaceInspectorView(section: .runtime)
}
