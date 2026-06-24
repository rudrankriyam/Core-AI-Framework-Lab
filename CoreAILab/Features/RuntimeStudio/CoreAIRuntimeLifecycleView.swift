import SwiftUI

struct CoreAIRuntimeLifecycleView: View {
    @Bindable var coordinator: CoreAIRunLifecycleCoordinator
    let context: CoreAIRuntimeRunContext

    var body: some View {
        if let run = coordinator.latestRun(for: context.experienceID) {
            Section {
                LabeledContent("Status") {
                    Label(run.state.title, systemImage: run.state.systemImage)
                }
                LabeledContent("Timing class", value: run.timingClass.title)
                LabeledContent("Model identity", value: run.modelIdentity)
                if let durationSeconds = run.durationSeconds {
                    LabeledContent("Elapsed") {
                        Text(
                            durationSeconds,
                            format: .number.precision(.fractionLength(3))
                        )
                        Text("seconds")
                    }
                }
                if let comparison = run.selectedComparisonIdentity {
                    LabeledContent(
                        "Comparison identity",
                        value: comparison.displayName
                    )
                }
                LabeledContent("Summary", value: run.summary)
            } header: {
                Label("Run Record", systemImage: "clock")
            }
        }
    }
}
