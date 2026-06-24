import SwiftUI

struct CoreAIRuntimeRecordingControlsView: View {
    let projects: [LabProject]
    @Binding var selectedProjectID: UUID?
    @Bindable var coordinator: CoreAIRunLifecycleCoordinator

    var body: some View {
        Section {
            Picker("Record in project", selection: $selectedProjectID) {
                Text("Off")
                    .tag(nil as UUID?)
                ForEach(projects) { project in
                    Text(project.name)
                        .tag(project.id as UUID?)
                }
            }
            .disabled(
                coordinator.hasActiveRuns
                    || coordinator.hasPendingPersistenceWrites
            )

            Picker(
                "Comparison identity",
                selection: $coordinator.selectedComparisonIdentity
            ) {
                Text("None")
                    .tag(nil as CoreAIRuntimeComparisonIdentity?)
                ForEach(coordinator.comparisonOptions) { identity in
                    Text(identity.displayName)
                        .tag(identity as CoreAIRuntimeComparisonIdentity?)
                    }
            }

            DisclosureGroup {
                VStack(alignment: .leading) {
                    Label("Cold and Warm Timing", systemImage: "thermometer.variable")
                        .bold()
                    Text("Attempts remain cold until one run succeeds for the imported model in this Runtime Studio session. Later runs with the same experience and model identity are warm.")

                    Divider()

                    Label("Comparison Identity", systemImage: "arrow.left.arrow.right")
                        .bold()
                    Text("A comparison identity records the intended comparator only. It does not claim that outputs were compared.")

                    Divider()

                    Label("Recipe Provenance", systemImage: "checkmark.seal")
                        .bold()
                    Text("A registry recipe is an import intent. Runtime Studio records unverified_intent until artifact-bound provenance proves the project recipe revision.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } label: {
                Label("How Run Evidence Works", systemImage: "info.circle")
            }

            if let persistenceMessage = coordinator.persistenceMessage {
                Label(persistenceMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            if coordinator.hasPendingPersistenceWrites {
                Button(
                    "Retry Run Recording",
                    systemImage: "arrow.clockwise",
                    action: coordinator.retryPendingPersistence
                )
            }
        } header: {
            Label("Run Recording", systemImage: "record.circle")
        }
    }
}
