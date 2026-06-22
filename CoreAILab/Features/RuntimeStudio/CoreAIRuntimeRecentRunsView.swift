import SwiftUI

struct CoreAIRuntimeRecentRunsView: View {
    @Bindable var coordinator: CoreAIRunLifecycleCoordinator

    var body: some View {
        if !coordinator.history.isEmpty {
            Section("Recent Runtime Runs") {
                ForEach(coordinator.history.prefix(8)) { run in
                    VStack(alignment: .leading) {
                        Label(
                            run.context.experienceTitle,
                            systemImage: run.state.systemImage
                        )
                        LabeledContent("Status", value: run.state.title)
                        LabeledContent("Timing class", value: run.timingClass.title)
                        if let durationSeconds = run.durationSeconds {
                            LabeledContent("Elapsed") {
                                Text(
                                    durationSeconds,
                                    format: .number.precision(.fractionLength(3))
                                )
                                Text("seconds")
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
