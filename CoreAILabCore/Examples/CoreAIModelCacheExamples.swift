import CoreAI
import Foundation

struct CoreAICacheExampleReport: Sendable, Equatable {
    let usesDefaultCache: Bool
    let appGroupCacheAvailable: Bool
    let defaultPolicyDescription: String
    let persistentPolicyDescription: String
    let sourceSensitivePolicyDescription: String
}

enum CoreAIModelCacheExamples {
    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func describeCache(appGroupIdentifier: String? = nil) -> CoreAICacheExampleReport {
        let appGroupCache = appGroupIdentifier.flatMap(AIModelCache.init(appGroup:))
        let sourceSensitivePolicy = AIModelCache.Policy(
            purgeConditions: [.storagePressure, .sourceAssetChangedOrDeleted]
        )

        return CoreAICacheExampleReport(
            usesDefaultCache: true,
            appGroupCacheAvailable: appGroupCache != nil,
            defaultPolicyDescription: describe(AIModelCache.Policy.default),
            persistentPolicyDescription: describe(AIModelCache.Policy.persistent),
            sourceSensitivePolicyDescription: describe(sourceSensitivePolicy)
        )
    }

    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func cachedModelIfAvailable(at url: URL, options: SpecializationOptions = .default) throws -> AIModel? {
        try AIModelCache.default.model(for: url, options: options)
    }

    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func clearCachedSpecializations(for url: URL) throws {
        try AIModelCache.default.deleteEntries(for: url)
    }

    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    private static func describe(_ policy: AIModelCache.Policy) -> String {
        var conditions: [String] = []
        if policy.purgeConditions.contains(.storagePressure) {
            conditions.append("storage pressure")
        }
        if policy.purgeConditions.contains(.sourceAssetChangedOrDeleted) {
            conditions.append("source changed/deleted")
        }
        if conditions.isEmpty {
            conditions.append("no automatic purge conditions")
        }
        return conditions.joined(separator: ", ")
    }
}
