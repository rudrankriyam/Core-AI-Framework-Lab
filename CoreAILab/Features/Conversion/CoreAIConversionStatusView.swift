#if os(macOS)
import SwiftUI

struct CoreAIConversionStatusView: View {
    let phase: CoreAIConversionPhase
    let statusMessage: String
    let processIdentifier: Int32?
    let duration: Duration?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(phase.title, systemImage: phase.systemImage)
                    .font(.title2.bold())

                Spacer()

                if phase.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Conversion in progress")
                }
            }

            Text(statusMessage)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                if let processIdentifier {
                    Label("PID \(processIdentifier)", systemImage: "terminal")
                }
                if let duration {
                    Label(
                        duration.formatted(.time(pattern: .minuteSecond)),
                        systemImage: "clock"
                    )
                }
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
#endif
