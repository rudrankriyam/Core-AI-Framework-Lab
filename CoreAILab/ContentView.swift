import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var selection: CoreAILabSection? = .projects

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Workspaces") {
                    ForEach(CoreAILabSection.workspaces) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                    }
                }

                Section("Tools") {
                    ForEach(CoreAILabSection.tools) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                    }
                }
            }
            .navigationTitle("Core AI Lab")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
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
