#if os(macOS)
import SwiftUI

struct CoreAIConversionEvidenceView: View {
    let workspace: CoreAIConversionWorkspaceModel
    let revealInFinder: (CoreAIConversionArtifact) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoreAIConversionStatusView(
                phase: workspace.phase,
                statusMessage: workspace.statusMessage,
                processIdentifier: workspace.processIdentifier,
                duration: workspace.duration
            )
            .padding()

            Divider()

            CoreAIConversionCommandView(command: workspace.commandPreview)
                .padding()

            Divider()

            CoreAIConversionLogView(entries: workspace.logEntries)
                .frame(minHeight: 220)

            if !workspace.artifacts.isEmpty || workspace.logURL != nil {
                Divider()
                CoreAIConversionOutputsView(
                    artifacts: workspace.artifacts,
                    logURL: workspace.logURL,
                    revealInFinder: revealInFinder
                )
                .padding()
            }
        }
        .background(.background)
    }
}
#endif
