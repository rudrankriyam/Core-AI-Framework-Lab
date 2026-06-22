import Foundation

struct CoreAIExperienceRegistry: Equatable, Sendable {
    let manifest: CoreAIExperienceRegistryManifest

    init(manifest: CoreAIExperienceRegistryManifest) throws {
        try Self.validate(manifest)
        self.manifest = manifest
    }

    var mappings: [CoreAIRecipeExperienceMapping] {
        manifest.mappings.sorted { first, second in
            if first.experience.workload.sortOrder != second.experience.workload.sortOrder {
                return first.experience.workload.sortOrder < second.experience.workload.sortOrder
            }
            return first.experience.title.localizedStandardCompare(second.experience.title)
                == .orderedAscending
        }
    }

    func mapping(id: String) -> CoreAIRecipeExperienceMapping? {
        manifest.mappings.first { $0.id == id }
    }

    func mappings(
        supportedOn platform: AppleCoreAIPlatform
    ) -> [CoreAIRecipeExperienceMapping] {
        mappings.filter { $0.experience.platforms.contains(platform) }
    }

    func mapping(
        id: String,
        supportedOn platform: AppleCoreAIPlatform
    ) -> CoreAIRecipeExperienceMapping? {
        mapping(id: id).flatMap { mapping in
            mapping.experience.platforms.contains(platform) ? mapping : nil
        }
    }

    static func decode(_ data: Data) throws -> CoreAIExperienceRegistry {
        let manifest = try JSONDecoder().decode(
            CoreAIExperienceRegistryManifest.self,
            from: data
        )
        return try CoreAIExperienceRegistry(manifest: manifest)
    }

    static func load(bundle: Bundle = .main) throws -> CoreAIExperienceRegistry {
        guard let url = bundle.url(
            forResource: "runtime-experiences",
            withExtension: "json",
            subdirectory: "RuntimeStudio"
        ) ?? bundle.url(
            forResource: "runtime-experiences",
            withExtension: "json"
        ) else {
            throw CoreAIExperienceRegistryError.resourceMissing
        }
        return try decode(Data(contentsOf: url))
    }

    private static func validate(_ manifest: CoreAIExperienceRegistryManifest) throws {
        guard manifest.schemaVersion == CoreAIExperienceRegistryManifest.currentSchemaVersion else {
            throw CoreAIExperienceRegistryError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        guard !manifest.mappings.isEmpty else {
            throw CoreAIExperienceRegistryError.missingMappings
        }

        var identifiers = Set<String>()
        for mapping in manifest.mappings {
            try requireValue(mapping.recipeIdentifier, path: "recipeIdentifier")
            try requireValue(mapping.recipeRevision, path: "recipeRevision")
            let experience = mapping.experience
            try requireValue(experience.id, path: "experience.id")
            try requireValue(experience.title, path: "experience.title")
            try requireValue(experience.summary, path: "experience.summary")
            try requireValue(experience.modelIdentifier, path: "experience.modelIdentifier")
            try requireValue(experience.systemImage, path: "experience.systemImage")

            guard identifiers.insert(experience.id).inserted else {
                throw CoreAIExperienceRegistryError.duplicateExperienceIdentifier(experience.id)
            }
            guard experience.adapter.supports(experience.workload) else {
                throw CoreAIExperienceRegistryError.incompatibleAdapter(
                    experienceID: experience.id
                )
            }
            guard supportsModelPreset(experience) else {
                throw CoreAIExperienceRegistryError.unsupportedModelPreset(
                    experienceID: experience.id,
                    modelIdentifier: experience.modelIdentifier
                )
            }
            guard !experience.capabilities.isEmpty else {
                throw CoreAIExperienceRegistryError.missingCapabilities(
                    experienceID: experience.id
                )
            }
            guard Set(experience.capabilities).count == experience.capabilities.count else {
                throw CoreAIExperienceRegistryError.repeatedCapability(
                    experienceID: experience.id
                )
            }
            guard !experience.platforms.isEmpty else {
                throw CoreAIExperienceRegistryError.missingPlatforms(
                    experienceID: experience.id
                )
            }
            guard Set(experience.platforms).count == experience.platforms.count else {
                throw CoreAIExperienceRegistryError.repeatedPlatform(
                    experienceID: experience.id
                )
            }
        }
    }

    private static func requireValue(_ value: String, path: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoreAIExperienceRegistryError.emptyValue(path)
        }
    }

    private static func supportsModelPreset(
        _ experience: CoreAIExperienceDescriptor
    ) -> Bool {
        switch experience.adapter {
        case .appleAudioTranscription:
            AppleAudioExample(shortName: experience.modelIdentifier) != nil
        case .appleDiffusion:
            AppleDiffusionExample(shortName: experience.modelIdentifier) != nil
        case .appleLanguage:
            AppleLanguageExample(shortName: experience.modelIdentifier) != nil
        case .appleObjectDetection:
            experience.modelIdentifier == "yolos-tiny"
        case .appleSegmentation:
            AppleSegmentationExample(shortName: experience.modelIdentifier) != nil
        case .genericFunctionWorkbench:
            true
        }
    }
}
