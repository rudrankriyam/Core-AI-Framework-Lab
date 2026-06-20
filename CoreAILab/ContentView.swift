import SwiftUI

struct ContentView: View {
    @State private var selection: CoreAILabSection? = .appleModels

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Workspaces") {
                    NavigationLink(value: CoreAILabSection.appleModels) {
                        Label(
                            CoreAILabSection.appleModels.title,
                            systemImage: CoreAILabSection.appleModels.systemImage
                        )
                    }

                    NavigationLink(value: CoreAILabSection.chatterbox) {
                        Label(
                            CoreAILabSection.chatterbox.title,
                            systemImage: CoreAILabSection.chatterbox.systemImage
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
                }
            }
            .navigationTitle("Core AI Lab")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            switch selection ?? .appleModels {
            case .appleModels:
                AppleModelLibraryView()
            case .chatterbox:
                ChatterboxWorkspaceView()
            case .assetInspector:
                CoreAIAssetInspectorView()
            case .runtime:
                CoreAIRuntimeView()
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
}

#Preview {
    ContentView()
}
