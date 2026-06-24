import SwiftUI

struct CoreAISpecializationControlsView: View {
    @Bindable var workspace: CoreAIAssetWorkspaceModel
    var isInteractionDisabled = false
    var allowsCacheRemoval = true

    var body: some View {
        Section {
            Picker("Compute profile", selection: $workspace.selectedProfile) {
                ForEach(CoreAISpecializationProfile.allCases) { profile in
                    Text(profile.title)
                        .tag(profile)
                        .disabled(!profile.isAvailable)
                }
            }
            .disabled(workspace.phase.isBusy || isInteractionDisabled)
            .onChange(of: workspace.selectedProfile) {
                refreshCacheStatus()
            }
            .help(workspace.selectedProfile.detail)

            Toggle(
                "Expect frequent input reshapes",
                isOn: $workspace.expectFrequentReshapes
            )
            .disabled(workspace.phase.isBusy || isInteractionDisabled)
            .onChange(of: workspace.expectFrequentReshapes) {
                refreshCacheStatus()
            }
            .help(
                "This setting is part of the cache identity. Measure both configurations for dynamic-shape workloads."
            )

            LabeledContent("Selected configuration") {
                Label(
                    workspace.cacheStatus.title,
                    systemImage: workspace.cacheStatus.systemImage
                )
            }

            if let result = workspace.specializationResult {
                LabeledContent("Last load") {
                    Text(result.loadedFromCache ? "Loaded from cache" : "Specialized on device")
                }
                LabeledContent("Duration") {
                    Text(result.duration.formatted(.time(pattern: .minuteSecond)))
                }
                LabeledContent("Runtime functions", value: result.functionNames.count, format: .number)
            }

            HStack {
                Button("Check Cache", systemImage: "arrow.clockwise", action: refreshCacheStatus)
                Button("Specialize", systemImage: "cpu", action: specialize)
                    .buttonStyle(.borderedProminent)
                    .disabled(!workspace.canSpecialize)

                if allowsCacheRemoval {
                    Menu("Remove Cache", systemImage: "trash") {
                        Button(
                            "Selected Configuration",
                            systemImage: "minus.circle",
                            role: .destructive,
                            action: prepareSelectedProfileRemoval
                        )
                        .disabled(workspace.cacheStatus != .cached)

                        Button(
                            "All Configurations for This Asset",
                            systemImage: "trash",
                            role: .destructive,
                            action: prepareAssetRemoval
                        )
                    }
                    .help(
                        allowsCacheRemoval
                            ? "Core AI exposes hit, miss, and deletion for this known asset."
                            : "Remove project-owned cache configurations from the artifact detail screen."
                    )
                    .confirmationDialog(
                        workspace.cacheRemovalTitle,
                        isPresented: $workspace.isConfirmingCacheRemoval,
                        titleVisibility: .visible
                    ) {
                        Button(
                            workspace.cacheRemovalTitle,
                            role: .destructive,
                            action: removePreparedCacheEntry
                        )
                    } message: {
                        Text(workspace.cacheRemovalMessage)
                    }
                }
            }
            .disabled(workspace.phase.isBusy || isInteractionDisabled)

            if workspace.phase.isBusy {
                ProgressView(operationTitle)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        } header: {
            Label("Specialization & Cache", systemImage: "cpu")
        }
    }

    private var operationTitle: String {
        switch workspace.phase {
        case .inspecting:
            "Inspecting model…"
        case .checkingCache:
            "Checking specialization cache…"
        case .specializing:
            "Specializing model…"
        case .removingCache:
            "Deleting cached specialization…"
        case .idle, .ready:
            "Updating Core AI state…"
        }
    }

    private func refreshCacheStatus() {
        Task {
            await workspace.refreshCacheStatus()
        }
    }

    private func specialize() {
        Task {
            await workspace.specialize()
        }
    }

    private func prepareSelectedProfileRemoval() {
        workspace.prepareCacheRemoval(.selectedProfile)
    }

    private func prepareAssetRemoval() {
        workspace.prepareCacheRemoval(.allProfilesForAsset)
    }

    private func removePreparedCacheEntry() {
        Task {
            await workspace.removePreparedCacheEntry()
        }
    }
}
