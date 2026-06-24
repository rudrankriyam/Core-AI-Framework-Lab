import SwiftData
import SwiftUI

struct ContentView: View {
    @SceneStorage("CoreAILab.selectedSection")
    private var selection: CoreAILabSection?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Library") {
                    ForEach(CoreAILabSection.library) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                        .help(section.summary)
                        .accessibilityHint(section.summary)
                    }
                }

                Section("Build") {
                    ForEach(CoreAILabSection.build) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                        .help(section.summary)
                        .accessibilityHint(section.summary)
                    }
                }

                Section("Run") {
                    ForEach(CoreAILabSection.run) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                        .help(section.summary)
                        .accessibilityHint(section.summary)
                    }
                }

                Section("Validate") {
                    ForEach(CoreAILabSection.validate) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                        .help(section.summary)
                        .accessibilityHint(section.summary)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        } detail: {
            switch selection ?? .projects {
            case .projects:
                CoreAIProjectLibraryView()
            case .appleModels:
                AppleModelLibraryView()
            case .recipes:
                CoreAIRecipeCatalogView()
            case .conversion:
                NavigationStack {
                    CoreAIConversionWorkspaceView()
                }
            case .recipeStudio:
                CoreAIRecipeStudioView()
            case .chatterbox:
                ChatterboxWorkspaceView()
            case .diarization:
                SpeakerDiarizationWorkspaceView()
            case .assetInspector:
                CoreAIAssetInspectorView()
            case .runtime:
                CoreAIRuntimeStudioView()
            case .deviceLab:
                NavigationStack {
                    CoreAIDeviceLabView()
                }
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .formStyle(.grouped)
        .tint(.blue)
#if os(macOS)
        .frame(minWidth: 1_000, minHeight: 680)
#endif
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [
                LabProject.self,
                ModelArtifactRecord.self,
                ProjectArtifactLink.self,
                CoreAIRecipeRevisionRecord.self,
                CoreAITargetProfileRecord.self,
                CoreAIRunRecord.self,
                CoreAIEvidenceRecord.self
            ],
            inMemory: true
        )
}
