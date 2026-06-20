import Foundation
@testable import CoreAILab

actor CoreAISpecializationServiceStub: CoreAIFunctionRuntimeServicing {
    private var cachedConfigurations: Set<CoreAISpecializationConfiguration>
    private var removedConfigurations: [CoreAISpecializationConfiguration] = []
    private var removedProfileURLs: [URL] = []
    private var removedAssetCount = 0
    private var removedAssetURLs: [URL] = []
    private var cacheLookupCount = 0
    private let delayedCacheLookup: Int?
    private let failingCacheLookups: Set<Int>
    private var contractLookupCount = 0
    private let contractResponses: [[CoreAIFunctionContract]]
    private let delayedContractLookup: Int?
    private let failingContractLookups: Set<Int>
    private let benchmarkRunDelay: Duration?
    private var completedBenchmarkRuns = 0

    init(
        cachedProfiles: Set<CoreAISpecializationProfile> = [],
        delayedCacheLookup: Int? = nil,
        failingCacheLookups: Set<Int> = [],
        contractResponses: [[CoreAIFunctionContract]] = [[]],
        delayedContractLookup: Int? = nil,
        failingContractLookups: Set<Int> = [],
        cachedConfigurations: Set<CoreAISpecializationConfiguration> = [],
        benchmarkRunDelay: Duration? = nil
    ) {
        self.cachedConfigurations = cachedConfigurations.union(
            cachedProfiles.map {
                CoreAISpecializationConfiguration(profile: $0)
            }
        )
        self.delayedCacheLookup = delayedCacheLookup
        self.failingCacheLookups = failingCacheLookups
        self.contractResponses = contractResponses
        self.delayedContractLookup = delayedContractLookup
        self.failingContractLookups = failingContractLookups
        self.benchmarkRunDelay = benchmarkRunDelay
    }

    func reset() {}

    func isCached(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) async throws -> Bool {
        cacheLookupCount += 1
        let lookup = cacheLookupCount
        if delayedCacheLookup == lookup {
            try await Task.sleep(for: .milliseconds(100))
        }
        if failingCacheLookups.contains(lookup) {
            throw CocoaError(.fileReadUnknown)
        }
        return cachedConfigurations.contains(configuration)
    }

    func specialize(
        at url: URL,
        configuration: CoreAISpecializationConfiguration,
        cachePolicy: CoreAICachePolicyChoice
    ) -> CoreAISpecializationResult {
        cachedConfigurations.insert(configuration)
        return CoreAISpecializationResult(
            configuration: configuration,
            duration: .milliseconds(25),
            loadedFromCache: false,
            functionNames: ["main"],
            bookmarkData: Data(configuration.profile.rawValue.utf8)
        )
    }

    func removeCachedEntry(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) {
        cachedConfigurations.remove(configuration)
        removedConfigurations.append(configuration)
        removedProfileURLs.append(url)
    }

    func removeCachedEntries(at url: URL) {
        cachedConfigurations.removeAll()
        removedAssetCount += 1
        removedAssetURLs.append(url)
    }

    func functionContracts() async throws -> [CoreAIFunctionContract] {
        contractLookupCount += 1
        let lookup = contractLookupCount
        if delayedContractLookup == lookup {
            try await Task.sleep(for: .milliseconds(100))
        }
        if failingContractLookups.contains(lookup) {
            throw CocoaError(.fileReadUnknown)
        }
        guard !contractResponses.isEmpty else { return [] }
        return contractResponses[min(lookup - 1, contractResponses.count - 1)]
    }

    func runFunction(
        named functionName: String,
        inputs: [CoreAIFunctionInputPlan]
    ) -> CoreAIFunctionRunResult {
        CoreAIFunctionRunResult(
            functionName: functionName,
            duration: .zero,
            outputs: []
        )
    }

    func benchmarkFunction(
        named functionName: String,
        inputs: [CoreAIFunctionInputPlan],
        configuration: CoreAIFunctionBenchmarkConfiguration
    ) async throws -> CoreAIFunctionBenchmarkResult {
        try configuration.validate()
        var warmupDurations: [Duration] = []
        for _ in 0..<configuration.warmupRuns {
            try Task.checkCancellation()
            await waitForBenchmarkRun()
            completedBenchmarkRuns += 1
            warmupDurations.append(.milliseconds(10))
            try Task.checkCancellation()
        }
        var trials: [CoreAIBenchmarkTrial] = []
        for index in 0..<configuration.measuredRuns {
            try Task.checkCancellation()
            await waitForBenchmarkRun()
            completedBenchmarkRuns += 1
            trials.append(
                CoreAIBenchmarkTrial(
                    index: index + 1,
                    duration: .milliseconds((index + 1) * 10)
                )
            )
            try Task.checkCancellation()
        }
        return CoreAIFunctionBenchmarkResult(
            functionName: functionName,
            functionLoadDuration: .milliseconds(2),
            inputPreparationDuration: .milliseconds(3),
            warmupDurations: warmupDurations,
            trials: trials,
            statistics: try CoreAIBenchmarkStatistics(trials: trials),
            outputs: [],
            environment: CoreAIBenchmarkEnvironment(
                capturedAt: Date(timeIntervalSince1970: 0),
                platform: "test",
                operatingSystem: "test",
                deviceArchitectureName: "test",
                availableComputeUnits: ["CPU"],
                buildConfiguration: .debug,
                startedThermalState: .nominal,
                endedThermalState: .nominal
            )
        )
    }

    func removalSnapshot() -> (
        configurations: [CoreAISpecializationConfiguration],
        assetCount: Int,
        profileURLs: [URL],
        assetURLs: [URL]
    ) {
        (
            removedConfigurations,
            removedAssetCount,
            removedProfileURLs,
            removedAssetURLs
        )
    }

    func completedBenchmarkRunCount() -> Int {
        completedBenchmarkRuns
    }

    private func waitForBenchmarkRun() async {
        guard let benchmarkRunDelay else { return }
        let activeRun = Task.detached {
            try? await Task.sleep(for: benchmarkRunDelay)
        }
        await activeRun.value
    }
}
