import SwiftUI

struct AppleModelLibraryView: View {
    @State private var model = AppleModelLibraryModel()

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Group {
                if let loadError = model.loadError {
                    ContentUnavailableView(
                        "Catalog Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if model.groups.isEmpty {
                    ContentUnavailableView.search
                } else {
                    List {
                        Section {
                            AppleModelCatalogSourceView(
                                modelCount: model.modelCount,
                                sourceRevision: model.sourceRevision,
                                sourceRepositoryURL: model.sourceRepositoryURL
                            )
                        }

                        ForEach(model.groups) { group in
                            Section(group.category.rawValue) {
                                ForEach(group.models) { entry in
                                    NavigationLink(value: entry) {
                                        AppleModelRow(model: entry)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Apple Models")
            .searchable(text: $model.searchText, prompt: "Search models, families, and tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Category", selection: $model.selectedCategory) {
                        Text("All Categories")
                            .tag(nil as AppleCoreAIModelCategory?)
                        ForEach(AppleCoreAIModelCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.systemImage)
                                .tag(category as AppleCoreAIModelCategory?)
                        }
                    }
                }
            }
            .navigationDestination(for: AppleCoreAIModel.self) { entry in
                AppleModelDetailView(
                    model: entry,
                    sourceRevision: model.sourceRevision
                )
            }
            .navigationDestination(for: AppleModelLibraryRoute.self) { route in
                switch route {
                case .objectDetection:
                    AppleObjectDetectionWorkspaceView()
                case .segmentation(let example):
                    AppleSegmentationWorkspaceView(example: example)
                case .languageModel(let example):
                    AppleLanguageWorkspaceView(example: example)
                case .diffusion(let example):
                    AppleDiffusionWorkspaceView(example: example)
                case .audio(let example):
                    AppleAudioWorkspaceView(example: example)
                case .conversion(let modelID):
                    CoreAIConversionWorkspaceView(initialModelID: modelID)
                }
            }
        }
    }
}
