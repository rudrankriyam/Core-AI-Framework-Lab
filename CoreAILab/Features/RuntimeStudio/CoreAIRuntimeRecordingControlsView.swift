import SwiftUI

struct CoreAIRuntimeRecordingControlsView: View {
    let projects: [LabProject]
    @Binding var selectedProjectID: UUID?
    @Bindable var coordinator: CoreAIRunLifecycleCoordinator

    var body: some View {
        Section("Run Recording") {
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

            Text("Attempts remain cold until one run succeeds for the imported model in this Runtime Studio session; later runs with the same experience and model identity are warm.")
                .foregroundStyle(.secondary)

            Text("A comparison identity records the intended comparator only; this slice does not claim that outputs were compared.")
                .foregroundStyle(.secondary)

            Text("A registry recipe is an import intent. Runtime Studio checks the imported model family, but records unverified_intent and does not link a project recipe revision without artifact-bound provenance proof.")
                .foregroundStyle(.secondary)

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
        }
    }
}
