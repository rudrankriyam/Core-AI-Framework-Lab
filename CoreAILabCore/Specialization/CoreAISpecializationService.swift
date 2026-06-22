import CoreAI
import CoreVideo
import CryptoKit
import Foundation

actor CoreAISpecializationService: CoreAIFunctionRuntimeServicing {
    private let artifactDigester: any CoreAIArtifactDigesting
    private let modelCache: any CoreAIModelCacheAccessing
    private let cacheIdentityStore: CoreAISpecializationCacheIdentityStore
    private var model: AIModel?
    private var modelURL: URL?
    private var configuration: CoreAISpecializationConfiguration?
    private var specializationGeneration = UUID()
    private var activeSpecializationGeneration: UUID?
    private var hasActiveRun = false

    init(
        artifactDigester: any CoreAIArtifactDigesting = CoreAIArtifactStore.shared,
        modelCache: any CoreAIModelCacheAccessing = CoreAIDefaultModelCacheAccess(),
        cacheIdentityStore: CoreAISpecializationCacheIdentityStore =
            CoreAISpecializationCacheIdentityStore.shared
    ) {
        self.artifactDigester = artifactDigester
        self.modelCache = modelCache
        self.cacheIdentityStore = cacheIdentityStore
    }

    func reset() {
        guard !hasActiveRun else { return }
        specializationGeneration = UUID()
        activeSpecializationGeneration = nil
        model = nil
        modelURL = nil
        configuration = nil
    }

    func isCached(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) async throws -> Bool {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let artifactDigest = try await artifactDigester.digest(at: url)
        return try await cachedModel(
            at: url,
            configuration: configuration,
            artifactDigest: artifactDigest
        ) != nil
    }

    nonisolated static func isMissingCacheEntry(_ error: any Error) -> Bool {
        let cocoaError = error as NSError
        return cocoaError.domain == NSPOSIXErrorDomain
            && cocoaError.code == Int(POSIXError.Code.ENOENT.rawValue)
    }

    func specialize(
        at url: URL,
        configuration: CoreAISpecializationConfiguration,
        cachePolicy: CoreAICachePolicyChoice
    ) async throws -> CoreAISpecializationResult {
        guard !hasActiveRun else {
            throw CoreAIFunctionWorkbenchError.functionAlreadyRunning
        }
        let generation = UUID()
        specializationGeneration = generation
        activeSpecializationGeneration = generation
        defer {
            if activeSpecializationGeneration == generation {
                activeSpecializationGeneration = nil
            }
        }
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let artifactDigest = try await artifactDigester.digest(at: url)
        guard specializationGeneration == generation else {
            throw CancellationError()
        }

        let clock = ContinuousClock()
        let startedAt = clock.now
        let cachedModel = try await cachedModel(
            at: url,
            configuration: configuration,
            artifactDigest: artifactDigest
        )
        let loadedFromCache = cachedModel != nil
        let specializedModel: AIModel
        if let cachedModel {
            specializedModel = cachedModel
        } else {
            specializedModel = try await modelCache.specialize(
                at: url,
                configuration: configuration,
                cachePolicy: cachePolicy
            )
            do {
                try await cacheIdentityStore.recordIdentity(
                    CoreAISpecializationCacheIdentity(
                        artifactDigest: artifactDigest,
                        modelBookmarkData: specializedModel.bookmarkData
                    ),
                    for: url,
                    configuration: configuration
                )
            } catch {
                try? await modelCache.deleteEntry(
                    at: url,
                    configuration: configuration
                )
                throw error
            }
        }

        guard specializationGeneration == generation else {
            throw CancellationError()
        }
        model = specializedModel
        modelURL = url
        self.configuration = configuration
        return CoreAISpecializationResult(
            configuration: configuration,
            artifactDigest: artifactDigest,
            duration: startedAt.duration(to: clock.now),
            loadedFromCache: loadedFromCache,
            functionNames: specializedModel.functionNames.sorted(),
            bookmarkData: specializedModel.bookmarkData
        )
    }

    func removeCachedEntry(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) async throws {
        guard !hasActiveRun else {
            throw CoreAIFunctionWorkbenchError.functionAlreadyRunning
        }
        specializationGeneration = UUID()
        activeSpecializationGeneration = nil
        releaseLoadedModel(ifMatching: url, configuration: configuration)
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        try await modelCache.deleteEntry(at: url, configuration: configuration)
        try await cacheIdentityStore.removeIdentity(
            for: url,
            configuration: configuration
        )
    }

    func removeCachedEntries(at url: URL) async throws {
        guard !hasActiveRun else {
            throw CoreAIFunctionWorkbenchError.functionAlreadyRunning
        }
        specializationGeneration = UUID()
        activeSpecializationGeneration = nil
        if modelURL == url {
            reset()
        }
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        try await modelCache.deleteEntries(at: url)
        try await cacheIdentityStore.removeIdentities(for: url)
    }

    func functionContracts() throws -> [CoreAIFunctionContract] {
        guard activeSpecializationGeneration == nil else {
            throw CoreAIFunctionWorkbenchError.modelPreparationInProgress
        }
        guard let model else {
            throw CoreAIFunctionWorkbenchError.modelNotPrepared
        }
        return CoreAIFunctionContractBuilder.contracts(for: model)
    }

    func runFunction(
        named functionName: String,
        inputs inputPlans: [CoreAIFunctionInputPlan]
    ) async throws -> CoreAIFunctionRunResult {
        guard !hasActiveRun else {
            throw CoreAIFunctionWorkbenchError.functionAlreadyRunning
        }
        guard activeSpecializationGeneration == nil else {
            throw CoreAIFunctionWorkbenchError.modelPreparationInProgress
        }
        let function = try loadValidatedFunction(named: functionName)

        hasActiveRun = true
        defer { hasActiveRun = false }

        let descriptor = function.descriptor
        let inputs = try makeInputs(for: descriptor, plans: inputPlans)

        let clock = ContinuousClock()
        let startedAt = clock.now
        var rawOutputs = try await function.run(inputs: inputs)
        let duration = startedAt.duration(to: clock.now)
        let summaries = try summarizeOutputs(
            &rawOutputs,
            descriptor: descriptor
        )
        return CoreAIFunctionRunResult(
            functionName: functionName,
            duration: duration,
            outputs: summaries
        )
    }

    func benchmarkFunction(
        named functionName: String,
        inputs inputPlans: [CoreAIFunctionInputPlan],
        configuration benchmarkConfiguration: CoreAIFunctionBenchmarkConfiguration
    ) async throws -> CoreAIFunctionBenchmarkResult {
        try benchmarkConfiguration.validate()
        guard !hasActiveRun else {
            throw CoreAIFunctionWorkbenchError.functionAlreadyRunning
        }
        guard activeSpecializationGeneration == nil else {
            throw CoreAIFunctionWorkbenchError.modelPreparationInProgress
        }

        let startedThermalState = CoreAIThermalState.current
        let clock = SuspendingClock()
        let model = try validatedModel(forFunctionNamed: functionName)
        let loadStartedAt = clock.now
        guard let function = try model.loadFunction(named: functionName) else {
            throw CoreAIFunctionWorkbenchError.functionUnavailable(functionName)
        }
        let functionLoadDuration = loadStartedAt.duration(to: clock.now)
        let descriptor = function.descriptor
        let inputPreparationStartedAt = clock.now
        let inputs = try makeInputs(for: descriptor, plans: inputPlans)
        let inputPreparationDuration = inputPreparationStartedAt.duration(to: clock.now)

        hasActiveRun = true
        defer { hasActiveRun = false }

        var warmupDurations: [Duration] = []
        warmupDurations.reserveCapacity(benchmarkConfiguration.warmupRuns)
        for _ in 0..<benchmarkConfiguration.warmupRuns {
            try Task.checkCancellation()
            let startedAt = clock.now
            _ = try await function.run(inputs: inputs)
            warmupDurations.append(startedAt.duration(to: clock.now))
            try Task.checkCancellation()
        }

        var trials: [CoreAIBenchmarkTrial] = []
        trials.reserveCapacity(benchmarkConfiguration.measuredRuns)
        var summaries: [CoreAIFunctionOutputSummary] = []
        var stoppedEarly = false
        for index in 0..<benchmarkConfiguration.measuredRuns {
            if Task.isCancelled {
                guard !trials.isEmpty else { throw CancellationError() }
                stoppedEarly = true
                break
            }
            let startedAt = clock.now
            var rawOutputs = try await function.run(inputs: inputs)
            let duration = startedAt.duration(to: clock.now)
            trials.append(CoreAIBenchmarkTrial(index: index + 1, duration: duration))
            summaries = try summarizeOutputs(
                &rawOutputs,
                descriptor: descriptor
            )
            if Task.isCancelled {
                stoppedEarly = trials.count < benchmarkConfiguration.measuredRuns
                break
            }
        }

        let statistics = try CoreAIBenchmarkStatistics(trials: trials)
        let endedThermalState = CoreAIThermalState.current
        return CoreAIFunctionBenchmarkResult(
            functionName: functionName,
            functionLoadDuration: functionLoadDuration,
            inputPreparationDuration: inputPreparationDuration,
            warmupDurations: warmupDurations,
            trials: trials,
            stoppedEarly: stoppedEarly,
            statistics: statistics,
            outputs: summaries,
            environment: .current(
                startedThermalState: startedThermalState,
                endedThermalState: endedThermalState
            )
        )
    }

    private func loadValidatedFunction(
        named functionName: String
    ) throws -> InferenceFunction {
        let model = try validatedModel(forFunctionNamed: functionName)
        guard let function = try model.loadFunction(named: functionName) else {
            throw CoreAIFunctionWorkbenchError.functionUnavailable(functionName)
        }
        return function
    }

    private func validatedModel(
        forFunctionNamed functionName: String
    ) throws -> AIModel {
        guard let model else {
            throw CoreAIFunctionWorkbenchError.modelNotPrepared
        }
        let contracts = CoreAIFunctionContractBuilder.contracts(for: model)
        guard let contract = contracts.first(where: { $0.name == functionName }) else {
            throw CoreAIFunctionWorkbenchError.functionUnavailable(functionName)
        }
        if let unsupportedReason = contract.unsupportedReason {
            throw CoreAIFunctionWorkbenchError.unsupportedFunction(unsupportedReason)
        }
        return model
    }

    private func makeInputs(
        for descriptor: InferenceFunctionDescriptor,
        plans inputPlans: [CoreAIFunctionInputPlan]
    ) throws -> [String: NDArray] {
        var inputs: [String: NDArray] = [:]
        for inputName in descriptor.inputNames {
            guard let inputPlan = inputPlans.first(where: { $0.name == inputName }) else {
                throw CoreAIFunctionWorkbenchError.missingInput(inputName)
            }
            guard case .ndArray(let tensorDescriptor)? = descriptor.inputDescriptor(
                of: inputName
            ) else {
                throw CoreAIFunctionWorkbenchError.unsupportedFunction(
                    "Input \(inputName) is not an NDArray."
                )
            }
            inputs[inputName] = try CoreAITensorFactory.makeArray(
                descriptor: tensorDescriptor,
                plan: inputPlan
            )
        }
        return inputs
    }

    private func summarizeOutputs(
        _ rawOutputs: inout InferenceFunction.Outputs,
        descriptor: InferenceFunctionDescriptor
    ) throws -> [CoreAIFunctionOutputSummary] {
        let returnedNames = Array(rawOutputs.names)
        let orderedNames = descriptor.outputNames + returnedNames.filter {
            !descriptor.outputNames.contains($0)
        }
        var summaries: [CoreAIFunctionOutputSummary] = []
        for outputName in orderedNames {
            guard let value = rawOutputs.remove(outputName) else {
                throw CoreAIFunctionWorkbenchError.missingOutput(outputName)
            }
            let kind = value.kind
            switch kind {
            case .ndArray:
                guard let array = value.ndArray else {
                    throw CoreAIFunctionWorkbenchError.missingOutput(outputName)
                }
                summaries.append(CoreAIOutputInspector.summarize(name: outputName, array: array))
            case .image:
                guard let image = value.pixelBuffer else {
                    throw CoreAIFunctionWorkbenchError.missingOutput(outputName)
                }
                summaries.append(
                    CoreAIOutputInspector.imageSummary(
                        name: outputName,
                        width: image.size.width,
                        height: image.size.height,
                        pixelFormatType: image.pixelFormatType.rawValue
                    )
                )
            @unknown default:
                summaries.append(
                    CoreAIFunctionOutputSummary(
                        name: outputName,
                        typeDescription: "unknown",
                        shape: [],
                        strides: [],
                        elementCount: 0,
                        sampledElementCount: 0,
                        minimum: nil,
                        maximum: nil,
                        mean: nil,
                        nonFiniteCount: 0,
                        preview: []
                    )
                )
            }
        }
        return summaries
    }

    private func releaseLoadedModel(
        ifMatching url: URL,
        configuration: CoreAISpecializationConfiguration
    ) {
        guard modelURL == url, self.configuration == configuration else { return }
        reset()
    }

    private func cachedModel(
        at url: URL,
        configuration: CoreAISpecializationConfiguration,
        artifactDigest: CoreAIArtifactDigest
    ) async throws -> AIModel? {
        let cachedModel: AIModel?
        do {
            cachedModel = try await modelCache.model(
                at: url,
                configuration: configuration
            )
        } catch {
            guard Self.isMissingCacheEntry(error) else { throw error }
            cachedModel = nil
        }

        guard let cachedModel else {
            try await cacheIdentityStore.removeIdentity(
                for: url,
                configuration: configuration
            )
            return nil
        }

        let recordedIdentity = try await cacheIdentityStore.identity(
            for: url,
            configuration: configuration
        )
        guard recordedIdentity?.artifactDigest == artifactDigest,
              recordedIdentity?.modelBookmarkData == cachedModel.bookmarkData else {
            do {
                try await modelCache.deleteEntry(
                    at: url,
                    configuration: configuration
                )
            } catch {
                guard Self.isMissingCacheEntry(error) else { throw error }
            }
            try await cacheIdentityStore.removeIdentity(
                for: url,
                configuration: configuration
            )
            return nil
        }
        return cachedModel
    }
}

struct CoreAISpecializationCacheIdentity: Codable, Equatable, Sendable {
    let artifactDigest: CoreAIArtifactDigest
    let modelBookmarkData: Data
}

protocol CoreAIModelCacheAccessing: Sendable {
    func model(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) async throws -> AIModel?
    func specialize(
        at url: URL,
        configuration: CoreAISpecializationConfiguration,
        cachePolicy: CoreAICachePolicyChoice
    ) async throws -> AIModel
    func deleteEntry(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) async throws
    func deleteEntries(at url: URL) async throws
}

struct CoreAIDefaultModelCacheAccess: CoreAIModelCacheAccessing {
    func model(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) async throws -> AIModel? {
        try AIModelCache.default.model(
            for: url,
            options: configuration.options
        )
    }

    func specialize(
        at url: URL,
        configuration: CoreAISpecializationConfiguration,
        cachePolicy: CoreAICachePolicyChoice
    ) async throws -> AIModel {
        try await AIModel.specialize(
            contentsOf: url,
            options: configuration.options,
            cache: .default,
            cachePolicy: cachePolicy.policy
        )
    }

    func deleteEntry(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) async throws {
        try AIModelCache.default.deleteEntry(
            for: url,
            options: configuration.options
        )
    }

    func deleteEntries(at url: URL) async throws {
        try AIModelCache.default.deleteEntries(for: url)
    }
}

actor CoreAISpecializationCacheIdentityStore {
    nonisolated static let shared = CoreAISpecializationCacheIdentityStore()

    private static let keyScheme = "CoreAISpecializationCacheIdentity/v1"
    private let rootURL: URL
    private let fileManager: FileManager

    init(
        rootURL: URL = CoreAIStorageLocation.rootURL.appending(
            path: "SpecializationCacheIdentities",
            directoryHint: .isDirectory
        ),
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func identity(
        for url: URL,
        configuration: CoreAISpecializationConfiguration
    ) throws -> CoreAISpecializationCacheIdentity? {
        let identityURL = identityURL(for: url, configuration: configuration)
        guard fileManager.fileExists(atPath: identityURL.path) else { return nil }
        return try JSONDecoder().decode(
            CoreAISpecializationCacheIdentity.self,
            from: Data(contentsOf: identityURL)
        )
    }

    func recordIdentity(
        _ identity: CoreAISpecializationCacheIdentity,
        for url: URL,
        configuration: CoreAISpecializationConfiguration
    ) throws {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(identity).write(
            to: identityURL(for: url, configuration: configuration),
            options: .atomic
        )
    }

    func removeIdentity(
        for url: URL,
        configuration: CoreAISpecializationConfiguration
    ) throws {
        let identityURL = identityURL(for: url, configuration: configuration)
        guard fileManager.fileExists(atPath: identityURL.path) else { return }
        try fileManager.removeItem(at: identityURL)
    }

    func removeIdentities(for url: URL) throws {
        for profile in CoreAISpecializationProfile.allCases {
            for expectFrequentReshapes in [false, true] {
                try removeIdentity(
                    for: url,
                    configuration: CoreAISpecializationConfiguration(
                        profile: profile,
                        expectFrequentReshapes: expectFrequentReshapes
                    )
                )
            }
        }
    }

    private func identityURL(
        for url: URL,
        configuration: CoreAISpecializationConfiguration
    ) -> URL {
        let key = [
            Self.keyScheme,
            url.standardizedFileURL.path,
            configuration.profile.rawValue,
            String(configuration.expectFrequentReshapes),
        ].joined(separator: "\u{0}")
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return rootURL.appending(
            path: "\(digest).json",
            directoryHint: .notDirectory
        )
    }
}
