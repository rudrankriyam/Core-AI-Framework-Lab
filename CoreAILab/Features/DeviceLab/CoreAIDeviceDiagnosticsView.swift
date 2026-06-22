import SwiftUI

struct CoreAIDeviceDiagnosticsView: View {
    let diagnostics: [CoreAIDeviceDiagnostic]

    var body: some View {
        Section("Authoring and Compatibility") {
            ForEach(diagnostics) { diagnostic in
                LabeledContent {
                    Text(diagnostic.detail)
                        .foregroundStyle(.secondary)
                } label: {
                    Label(
                        diagnostic.title,
                        systemImage: diagnostic.severity.systemImage
                    )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(diagnostic.severity.title): \(diagnostic.title)"
                )
                .accessibilityValue(diagnostic.detail)
            }
        }
    }
}
