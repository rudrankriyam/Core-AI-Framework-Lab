import CoreAI
import Foundation

actor CoreAISpecializationService: CoreAISpecializationServicing {
    private var model: AIModel?
    private var modelURL: URL?
    private var profile: CoreAISpecializationProfile?
    private var specializationGeneration = UUID()

    func reset() {
        specializationGeneration = UUID()
        model = nil
        modelURL = nil
        profile = nil
    }

    func isCached(
        at url: URL,
        profile: CoreAISpecializationProfile
    ) throws -> Bool {
        try withSecurityScopedAccess(to: url) {
            try AIModelCache.default.model(for: url, options: profile.options) != nil
        }
    }

    func specialize(
        at url: URL,
        profile: CoreAISpecializationProfile,
        cachePolicy: CoreAICachePolicyChoice
    ) async throws -> CoreAISpecializationResult {
        let generation = UUID()
        specializationGeneration = generation
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let clock = ContinuousClock()
        let startedAt = clock.now
        let cachedModel = try AIModelCache.default.model(
            for: url,
            options: profile.options
        )
        let loadedFromCache = cachedModel != nil
        let specializedModel: AIModel
        if let cachedModel {
            specializedModel = cachedModel
        } else {
            specializedModel = try await AIModel.specialize(
                contentsOf: url,
                options: profile.options,
                cache: .default,
                cachePolicy: cachePolicy.policy
            )
        }

        guard specializationGeneration == generation else {
            throw CancellationError()
        }
        model = specializedModel
        modelURL = url
        self.profile = profile
        return CoreAISpecializationResult(
            duration: startedAt.duration(to: clock.now),
            loadedFromCache: loadedFromCache,
            functionNames: specializedModel.functionNames.sorted(),
            bookmarkData: specializedModel.bookmarkData
        )
    }

    func removeCachedEntry(
        at url: URL,
        profile: CoreAISpecializationProfile
    ) throws {
        specializationGeneration = UUID()
        releaseLoadedModel(ifMatching: url, profile: profile)
        try withSecurityScopedAccess(to: url) {
            try AIModelCache.default.deleteEntry(for: url, options: profile.options)
        }
    }

    func removeCachedEntries(at url: URL) throws {
        specializationGeneration = UUID()
        if modelURL == url {
            reset()
        }
        try withSecurityScopedAccess(to: url) {
            try AIModelCache.default.deleteEntries(for: url)
        }
    }

    private func releaseLoadedModel(
        ifMatching url: URL,
        profile: CoreAISpecializationProfile
    ) {
        guard modelURL == url, self.profile == profile else { return }
        reset()
    }

    private func withSecurityScopedAccess<Result>(
        to url: URL,
        operation: () throws -> Result
    ) rethrows -> Result {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }
}
