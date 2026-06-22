import Foundation
import Observation

@MainActor
@Observable
final class CoreAIRuntimeStudioModel {
    private(set) var registry: CoreAIExperienceRegistry?
    private(set) var loadError: String?
    var searchText = ""
    var selectedWorkload: CoreAIExperienceWorkload?

    @ObservationIgnored
    private let currentPlatform: AppleCoreAIPlatform

    init(
        currentPlatform: AppleCoreAIPlatform = .current,
        registry: CoreAIExperienceRegistry? = nil
    ) {
        self.currentPlatform = currentPlatform
        self.registry = registry
    }

    var availableMappings: [CoreAIRecipeExperienceMapping] {
        registry?.mappings(supportedOn: currentPlatform) ?? []
    }

    var filteredMappings: [CoreAIRecipeExperienceMapping] {
        availableMappings.filter { mapping in
            let matchesWorkload = selectedWorkload == nil
                || mapping.experience.workload == selectedWorkload
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || mapping.experience.title.localizedStandardContains(query)
                || mapping.experience.summary.localizedStandardContains(query)
                || mapping.experience.modelIdentifier.localizedStandardContains(query)
                || mapping.recipeIdentifier.localizedStandardContains(query)
            return matchesWorkload && matchesSearch
        }
    }

    var visibleWorkloads: [CoreAIExperienceWorkload] {
        let workloads = Set(filteredMappings.map(\.experience.workload))
        return workloads.sorted { $0.sortOrder < $1.sortOrder }
    }

    func mappings(for workload: CoreAIExperienceWorkload) -> [CoreAIRecipeExperienceMapping] {
        filteredMappings.filter { $0.experience.workload == workload }
    }

    func mapping(id: String) -> CoreAIRecipeExperienceMapping? {
        registry?.mapping(id: id, supportedOn: currentPlatform)
    }

    var comparisonOptions: [CoreAIRuntimeComparisonIdentity] {
        availableMappings.map(\.runContext.comparisonIdentity)
    }

    func load(bundle: Bundle = .main) {
        do {
            registry = try CoreAIExperienceRegistry.load(bundle: bundle)
            loadError = nil
        } catch {
            registry = nil
            loadError = error.localizedDescription
        }
    }
}
