import SwiftUI

struct CoreAISpecializationControlsView: View {
    @Bindable var workspace: CoreAIAssetWorkspaceModel
    var isInteractionDisabled = false

    var body: some View {
        Section("Specialization & Cache") {
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

            Text(workspace.selectedProfile.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle(
                "Expect frequent input reshapes",
                isOn: $workspace.expectFrequentReshapes
            )
            .disabled(workspace.phase.isBusy || isInteractionDisabled)
            .onChange(of: workspace.expectFrequentReshapes) {
                refreshCacheStatus()
            }

            Text(
                "This Core AI specialization option is part of the cache identity. Measure both settings for dynamic-shape workloads instead of assuming one is faster."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

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
            .disabled(workspace.phase.isBusy || isInteractionDisabled)

            if workspace.phase.isBusy {
                Label("Core AI operation in progress", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            }

            Text("Core AI exposes hit/miss and deletion for known assets, but not cache paths, entry sizes, or a complete inventory.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
