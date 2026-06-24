import SwiftUI

struct CoreAIPipelineValidationIssuesView: View {
    let issues: [CoreAIPipelineValidationIssue]

    var body: some View {
        if issues.isEmpty {
            Label("Contract Valid", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            ForEach(issues) { issue in
                VStack(alignment: .leading) {
                    Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                    Text(issue.location)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
