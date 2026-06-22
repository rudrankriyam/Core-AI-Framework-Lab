import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var selection: CoreAILabSection? = .projects

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Workspaces") {
                    NavigationLink(value: CoreAILabSection.projects) {
                        Label(
                            CoreAILabSection.projects.title,
                            systemImage: CoreAILabSection.projects.systemImage
                        )
                    }

                    NavigationLink(value: CoreAILabSection.appleModels) {
                        Label(
                            CoreAILabSection.appleModels.title,
                            systemImage: CoreAILabSection.appleModels.systemImage
                        )
                    }

                    NavigationLink(value: CoreAILabSection.conversion) {
                        Label(
                            CoreAILabSection.conversion.title,
                            systemImage: CoreAILabSection.conversion.systemImage
                        )
                    }

                    NavigationLink(value: CoreAILabSection.chatterbox) {
                        Label(
                            CoreAILabSection.chatterbox.title,
                            systemImage: CoreAILabSection.chatterbox.systemImage
                        )
                    }

                    NavigationLink(value: CoreAILabSection.diarization) {
                        Label(
                            CoreAILabSection.diarization.title,
                            systemImage: CoreAILabSection.diarization.systemImage
                        )
                    }
                }

                Section("Tools") {
                    NavigationLink(value: CoreAILabSection.assetInspector) {
                        Label(
                            CoreAILabSection.assetInspector.title,
                            systemImage: CoreAILabSection.assetInspector.systemImage
                        )
                    }

                    NavigationLink(value: CoreAILabSection.runtime) {
                        Label(
                            CoreAILabSection.runtime.title,
                            systemImage: CoreAILabSection.runtime.systemImage
                        )
                    }

                    NavigationLink(value: CoreAILabSection.deviceLab) {
                        Label(
                            CoreAILabSection.deviceLab.title,
                            systemImage: CoreAILabSection.deviceLab.systemImage
                        )
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
            case .conversion:
                NavigationStack {
                    CoreAIConversionWorkspaceView()
                }
            case .chatterbox:
                ChatterboxWorkspaceView()
            case .diarization:
                SpeakerDiarizationWorkspaceView()
            case .assetInspector:
                CoreAIAssetInspectorView()
            case .runtime:
                CoreAIRuntimeView()
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
