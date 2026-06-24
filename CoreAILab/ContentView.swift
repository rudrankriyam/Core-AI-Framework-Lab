import SwiftData
import SwiftUI

struct ContentView: View {
    @SceneStorage("CoreAILab.selectedSection")
    private var selection: CoreAILabSection?

    @SceneStorage("CoreAILab.isWorkspaceInspectorPresented")
    private var isWorkspaceInspectorPresented = false

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        let selectedSection = selection ?? .projects

        NavigationSplitView(columnVisibility: $columnVisibility) {
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
#if os(macOS)
            .toolbar(removing: .sidebarToggle)
#endif
        } detail: {
            switch selectedSection {
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
        .inspector(isPresented: $isWorkspaceInspectorPresented) {
            CoreAIWorkspaceInspectorView(section: selectedSection)
        }
        .toolbar {
#if os(macOS)
            ToolbarItem(placement: .navigation) {
                Button(
                    "Toggle Sidebar",
                    systemImage: "sidebar.leading",
                    action: toggleSidebar
                )
                .help("Show or hide the workspace sidebar")
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
#endif

            ToolbarItem(placement: .primaryAction) {
                Button(
                    "Workspace Inspector",
                    systemImage: "sidebar.trailing",
                    action: toggleWorkspaceInspector
                )
                .help("Show the selected workspace's workflow and evidence boundary")
#if os(macOS)
                .keyboardShortcut("0", modifiers: [.command, .option])
#endif
            }
        }
#if os(macOS)
        .frame(minWidth: 1_000, minHeight: 680)
#endif
    }

    private func toggleWorkspaceInspector() {
        isWorkspaceInspectorPresented.toggle()
    }

    private func toggleSidebar() {
        withAnimation {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
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
