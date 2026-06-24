import SwiftUI

struct CoreAIDeviceDiagnosticsView: View {
    let diagnostics: [CoreAIDeviceDiagnostic]

    var body: some View {
        Section {
            ForEach(diagnostics) { diagnostic in
                VStack(alignment: .leading) {
                    Label(
                        diagnostic.title,
                        systemImage: diagnostic.severity.systemImage
                    )
                    Text(diagnostic.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(diagnostic.severity.title): \(diagnostic.title)"
                )
                .accessibilityValue(diagnostic.detail)
            }
        } header: {
            Label("Compatibility Checks", systemImage: "checkmark.shield")
        }
    }
}
