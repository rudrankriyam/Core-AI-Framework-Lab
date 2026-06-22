import Foundation
import Testing
@testable import CoreAILab

@MainActor
struct CoreAIExperienceRegistryTests {
    @Test
    func bundledRegistryRoutesMultipleModelsThroughSharedAdapters() throws {
        let registry = try CoreAIExperienceRegistry.load()

        #expect(registry.manifest.schemaVersion == 1)
        #expect(registry.mappings.count == 10)
        let segmentation = registry.mappings.filter {
            $0.experience.adapter == .appleSegmentation
        }
        #expect(segmentation.map(\.experience.modelIdentifier).sorted() == [
            "efficient-sam-vitt",
            "sam3"
        ])
        let diffusion = registry.mappings.filter {
            $0.experience.adapter == .appleDiffusion
        }
        #expect(diffusion.count == 4)
        #expect(registry.mapping(id: "apple-qwen3-0.6b-language")?.experience.workload == .textGeneration)
        #expect(
            registry.mapping(id: "apple-qwen3-0.6b-language")?
                .runContext.recipeProvenance == .unverifiedIntent
        )
        #expect(registry.mapping(id: "apple-wav2vec2-transcription")?.experience.workload == .audioTranscription)
    }

    @Test
    func registryRejectsAnAdapterWorkloadMismatch() {
        let manifest = makeManifest(
            experience: makeExperience(
                workload: .audioTranscription,
                adapter: .appleLanguage
            )
        )

        #expect(
            throws: CoreAIExperienceRegistryError.incompatibleAdapter(
                experienceID: "test-experience"
            )
        ) {
            _ = try CoreAIExperienceRegistry(manifest: manifest)
        }
    }

    @Test
    func registryRejectsDuplicateExperienceIdentifiers() {
        let experience = makeExperience()
        let mapping = CoreAIRecipeExperienceMapping(
            recipeIdentifier: "test.recipe",
            recipeRevision: "1",
            experience: experience
        )
        let manifest = CoreAIExperienceRegistryManifest(
            schemaVersion: 1,
            mappings: [mapping, mapping]
        )

        #expect(
            throws: CoreAIExperienceRegistryError.duplicateExperienceIdentifier(
                "test-experience"
            )
        ) {
            _ = try CoreAIExperienceRegistry(manifest: manifest)
        }
    }

    @Test
    func registryRejectsARecipePresetTheSemanticAdapterCannotResolve() {
        let manifest = makeManifest(
            experience: makeExperience(modelIdentifier: "unknown-language-model")
        )

        #expect(
            throws: CoreAIExperienceRegistryError.unsupportedModelPreset(
                experienceID: "test-experience",
                modelIdentifier: "unknown-language-model"
            )
        ) {
            _ = try CoreAIExperienceRegistry(manifest: manifest)
        }
    }

    @Test
    func registryRejectsUnknownSchemaBeforeUsingMappings() {
        let manifest = CoreAIExperienceRegistryManifest(
            schemaVersion: 2,
            mappings: []
        )

        #expect(
            throws: CoreAIExperienceRegistryError.unsupportedSchemaVersion(2)
        ) {
            _ = try CoreAIExperienceRegistry(manifest: manifest)
        }
    }

    @Test
    func runtimeStudioExcludesPlatformIncompatibleRoutesAndComparisons() throws {
        let macMapping = CoreAIRecipeExperienceMapping(
            recipeIdentifier: "test.recipe.mac",
            recipeRevision: "1",
            experience: makeExperience(
                id: "mac-experience",
                platforms: [.macOS]
            )
        )
        let iOSMapping = CoreAIRecipeExperienceMapping(
            recipeIdentifier: "test.recipe.ios",
            recipeRevision: "1",
            experience: makeExperience(
                id: "ios-experience",
                platforms: [.iOS]
            )
        )
        let registry = try CoreAIExperienceRegistry(
            manifest: CoreAIExperienceRegistryManifest(
                schemaVersion: 1,
                mappings: [macMapping, iOSMapping]
            )
        )
        let macModel = CoreAIRuntimeStudioModel(
            currentPlatform: .macOS,
            registry: registry
        )
        let iOSModel = CoreAIRuntimeStudioModel(
            currentPlatform: .iOS,
            registry: registry
        )

        #expect(macModel.filteredMappings.map(\.id) == ["mac-experience"])
        #expect(macModel.mapping(id: "ios-experience") == nil)
        #expect(
            macModel.comparisonOptions.map(\.experienceID)
                == ["mac-experience"]
        )
        #expect(iOSModel.filteredMappings.map(\.id) == ["ios-experience"])
        #expect(iOSModel.mapping(id: "mac-experience") == nil)
        #expect(
            iOSModel.comparisonOptions.map(\.experienceID)
                == ["ios-experience"]
        )
    }

    @Test
    func missingRuntimeRouteExplainsWhyTheExperienceIsUnavailable() {
        let route = CoreAIRuntimeExperienceRoute(
            experienceID: "missing-experience"
        )

        #expect(route.unavailableDescription.contains("missing-experience"))
        #expect(route.unavailableDescription.contains("current runtime registry"))
    }

    private func makeManifest(
        experience: CoreAIExperienceDescriptor
    ) -> CoreAIExperienceRegistryManifest {
        CoreAIExperienceRegistryManifest(
            schemaVersion: 1,
            mappings: [
                CoreAIRecipeExperienceMapping(
                    recipeIdentifier: "test.recipe",
                    recipeRevision: "1",
                    experience: experience
                )
            ]
        )
    }

    private func makeExperience(
        id: String = "test-experience",
        workload: CoreAIExperienceWorkload = .textGeneration,
        adapter: CoreAIExperienceAdapter = .appleLanguage,
        modelIdentifier: String = "qwen3-0.6b",
        platforms: [AppleCoreAIPlatform] = [.macOS]
    ) -> CoreAIExperienceDescriptor {
        CoreAIExperienceDescriptor(
            id: id,
            title: "Test Experience",
            summary: "A deterministic fixture.",
            workload: workload,
            adapter: adapter,
            modelIdentifier: modelIdentifier,
            systemImage: "function",
            capabilities: [.coldWarmTiming],
            platforms: platforms
        )
    }
}
