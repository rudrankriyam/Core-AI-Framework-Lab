import Foundation
import Observation

@MainActor
@Observable
final class AppleModelLibraryModel {
    var searchText = ""
    var selectedCategory: AppleCoreAIModelCategory?

    private(set) var document: AppleCoreAIModelCatalogDocument?
    private(set) var loadError: String?

    init(bundle: Bundle = .main) {
        do {
            document = try AppleCoreAIModelCatalog.load(bundle: bundle)
        } catch {
            loadError = error.localizedDescription
        }
    }

    var sourceRevision: String {
        document?.sourceRevision ?? "unknown"
    }

    var sourceRepositoryURL: URL? {
        guard let sourceRepository = document?.sourceRepository else {
            return nil
        }
        return URL(string: sourceRepository)
    }

    var modelCount: Int {
        document?.models.count ?? 0
    }

    var groups: [AppleCoreAIModelGroup] {
        let models = document?.models.filter { model in
            model.matches(searchText)
                && (selectedCategory == nil || model.category == selectedCategory)
        } ?? []

        return AppleCoreAIModelCategory.allCases.compactMap { category in
            let categoryModels = models
                .filter { $0.category == category }
                .sorted { first, second in
                    if first.shortName == second.shortName {
                        return (first.variant ?? "") < (second.variant ?? "")
                    }
                    return first.shortName < second.shortName
                }
            guard !categoryModels.isEmpty else { return nil }
            return AppleCoreAIModelGroup(category: category, models: categoryModels)
        }
    }
}
