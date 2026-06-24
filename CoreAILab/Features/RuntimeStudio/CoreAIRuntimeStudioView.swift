import SwiftData
import SwiftUI

struct CoreAIRuntimeStudioView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LabProject.name) private var projects: [LabProject]
    @State private var model = CoreAIRuntimeStudioModel()
    @State private var coordinator = CoreAIRunLifecycleCoordinator()
    @State private var selectedProjectID: UUID?

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Group {
                if let loadError = model.loadError {
                    ContentUnavailableView(
                        "Couldn't Load Runtime Experiences",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if model.registry == nil {
                    ProgressView("Loading runtime experiences…")
                } else if model.filteredMappings.isEmpty {
                    ContentUnavailableView.search
                } else {
                    List {
                        CoreAIRuntimeRecordingControlsView(
                            projects: projects,
                            selectedProjectID: $selectedProjectID,
                            coordinator: coordinator
                        )
                        CoreAIRuntimeRecentRunsView(coordinator: coordinator)

                        ForEach(model.visibleWorkloads, id: \.self) { workload in
                            CoreAIRuntimeExperienceSectionView(
                                workload: workload,
                                mappings: model.mappings(for: workload)
                            )
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Runtime Studio")
            .searchable(
                text: $model.searchText,
                prompt: "Search experiences, models, and recipes"
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Workload", selection: $model.selectedWorkload) {
                        Text("All Workloads")
                            .tag(nil as CoreAIExperienceWorkload?)
                        ForEach(CoreAIExperienceWorkload.allCases, id: \.self) { workload in
                            Text(workload.title)
                                .tag(workload as CoreAIExperienceWorkload?)
                        }
                    }
                }
            }
            .navigationDestination(for: CoreAIRuntimeExperienceRoute.self) { route in
                if let mapping = model.mapping(id: route.experienceID) {
                    CoreAIRuntimeExperienceDestinationView(
                        mapping: mapping,
                        coordinator: coordinator
                    )
                } else {
                    ContentUnavailableView(
                        "Experience Not Found",
                        systemImage: "questionmark.folder",
                        description: Text(route.unavailableDescription)
                    )
                    .navigationTitle("Experience Not Found")
                }
            }
            .task {
                model.load()
                registerComparisons()
            }
            .onChange(of: selectedProjectID) {
                configurePersistence()
            }
            .onChange(of: projects.map(\.id)) {
                keepValidProjectSelection()
            }
        }
    }

    private func registerComparisons() {
        coordinator.registerComparisonOptions(model.comparisonOptions)
    }

    private func configurePersistence() {
        guard let selectedProjectID,
              let project = projects.first(where: { $0.id == selectedProjectID }) else {
            coordinator.configurePersistence(nil)
            return
        }
        let persistence = CoreAIProjectRunPersistence(
            project: project,
            modelContext: modelContext
        )
        coordinator.configurePersistence(persistence)
        coordinator.recoverInterruptedPersistence()
    }

    private func keepValidProjectSelection() {
        guard let selectedProjectID else { return }
        if !projects.contains(where: { $0.id == selectedProjectID }) {
            self.selectedProjectID = nil
        }
    }
}
