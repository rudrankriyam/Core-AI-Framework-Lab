import Foundation

enum CoreAIExperienceRegistryError: LocalizedError, Equatable {
    case duplicateExperienceIdentifier(String)
    case emptyValue(String)
    case incompatibleAdapter(experienceID: String)
    case missingCapabilities(experienceID: String)
    case missingMappings
    case missingPlatforms(experienceID: String)
    case repeatedCapability(experienceID: String)
    case repeatedPlatform(experienceID: String)
    case resourceMissing
    case unsupportedModelPreset(experienceID: String, modelIdentifier: String)
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .duplicateExperienceIdentifier(let identifier):
            "Runtime experience identifier \(identifier) appears more than once."
        case .emptyValue(let path):
            "Runtime registry value \(path) must not be empty."
        case .incompatibleAdapter(let experienceID):
            "Runtime experience \(experienceID) uses an adapter that does not support its workload."
        case .missingCapabilities(let experienceID):
            "Runtime experience \(experienceID) must declare its capabilities."
        case .missingMappings:
            "The Runtime Studio registry does not contain any recipe mappings."
        case .missingPlatforms(let experienceID):
            "Runtime experience \(experienceID) must declare at least one platform."
        case .repeatedCapability(let experienceID):
            "Runtime experience \(experienceID) repeats a capability."
        case .repeatedPlatform(let experienceID):
            "Runtime experience \(experienceID) repeats a platform."
        case .resourceMissing:
            "The bundled Runtime Studio registry is missing."
        case .unsupportedModelPreset(let experienceID, let modelIdentifier):
            "Runtime experience \(experienceID) maps unsupported model preset \(modelIdentifier)."
        case .unsupportedSchemaVersion(let version):
            "Runtime Studio registry schema \(version) is unsupported."
        }
    }
}
