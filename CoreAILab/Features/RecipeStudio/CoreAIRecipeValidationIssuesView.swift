import SwiftUI

struct CoreAIRecipeValidationIssuesView: View {
    let issues: [CoreAIRecipeValidationIssue]

    var body: some View {
        if issues.isEmpty {
            Label("This draft is structurally valid", systemImage: "checkmark.circle.fill")
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
