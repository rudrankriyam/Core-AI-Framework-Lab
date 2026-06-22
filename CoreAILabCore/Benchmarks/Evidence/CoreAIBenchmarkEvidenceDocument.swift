import Foundation

struct CoreAIBenchmarkEvidenceDocument: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let benchmarkID: UUID
    let artifact: CoreAIArtifactDigest
    let functionName: String
    let specialization: CoreAIBenchmarkEvidenceSpecialization
    let executionState: CoreAIBenchmarkEvidenceExecutionState
    let inputs: [CoreAIBenchmarkEvidenceInput]
    let functionLoadTiming: CoreAIBenchmarkEvidenceTiming
    let inputPreparationTiming: CoreAIBenchmarkEvidenceTiming
    let warmupRuns: [CoreAIBenchmarkEvidenceTrial]
    let measuredRuns: [CoreAIBenchmarkEvidenceTrial]
    let statistics: CoreAIBenchmarkEvidenceStatistics
    let outputs: [CoreAIBenchmarkEvidenceOutput]
    let benchmarkEnvironment: CoreAIBenchmarkEvidenceEnvironment
    let metrics: CoreAIBenchmarkEvidenceMetrics

    init(
        report: CoreAIFunctionBenchmarkReport,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        benchmarkID = report.id
        artifact = report.artifactDigest
        functionName = report.result.functionName
        specialization = CoreAIBenchmarkEvidenceSpecialization(
            configuration: report.specializationConfiguration
        )
        executionState = CoreAIBenchmarkEvidenceExecutionState(
            configuration: report.benchmarkConfiguration,
            loadedFromCache: report.loadedFromCache,
            stoppedEarly: report.result.stoppedEarly
        )
        inputs = report.inputPlans
            .sorted { $0.name < $1.name }
            .map(CoreAIBenchmarkEvidenceInput.init)
        functionLoadTiming = CoreAIBenchmarkEvidenceTiming(
            duration: report.result.functionLoadDuration
        )
        inputPreparationTiming = CoreAIBenchmarkEvidenceTiming(
            duration: report.result.inputPreparationDuration
        )
        warmupRuns = report.result.warmupDurations.enumerated().map {
            CoreAIBenchmarkEvidenceTrial(
                index: $0.offset + 1,
                timing: CoreAIBenchmarkEvidenceTiming(duration: $0.element)
            )
        }
        measuredRuns = report.result.trials.map {
            CoreAIBenchmarkEvidenceTrial(
                index: $0.index,
                timing: CoreAIBenchmarkEvidenceTiming(duration: $0.duration)
            )
        }
        statistics = CoreAIBenchmarkEvidenceStatistics(
            statistics: report.result.statistics
        )
        outputs = report.result.outputs
            .sorted { $0.name < $1.name }
            .map(CoreAIBenchmarkEvidenceOutput.init)
        benchmarkEnvironment = CoreAIBenchmarkEvidenceEnvironment(
            environment: report.result.environment
        )
        metrics = CoreAIBenchmarkEvidenceMetrics()
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CoreAIBenchmarkEvidenceError.unsupportedSchemaVersion(
                schemaVersion
            )
        }
        try validateArtifact()
        try validateText(functionName, field: "function name")
        try validateSpecialization()
        try validateExecutionState()
        try validateInputs()
        try functionLoadTiming.validate(field: "function-load timing")
        try inputPreparationTiming.validate(field: "input-preparation timing")
        try validateTrials(
            warmupRuns,
            requestedCount: executionState.requestedWarmupRuns,
            field: "warmup runs",
            allowsPartialCount: false
        )
        try validateTrials(
            measuredRuns,
            requestedCount: executionState.requestedMeasuredRuns,
            field: "measured runs",
            allowsPartialCount: executionState.stoppedEarly
        )
        try validateStatistics()
        try validateOutputs()
        try validateEnvironment()
        try validateMetrics()
    }

    private func validateArtifact() throws {
        guard artifact.scheme == CoreAIArtifactDigest.currentScheme,
              artifact.sha256.count == 64,
              artifact.sha256.allSatisfy(Self.isLowercaseHexDigit),
              artifact.byteCount >= 0,
              artifact.fileCount > 0 else {
            throw CoreAIBenchmarkEvidenceError.invalidField("artifact digest")
        }
    }

    private func validateSpecialization() throws {
        let profiles = Set(CoreAISpecializationProfile.allCases.map(\.rawValue))
        guard profiles.contains(specialization.profile) else {
            throw CoreAIBenchmarkEvidenceError.invalidField(
                "specialization profile"
            )
        }
        let expectedPreferredComputeUnit: String?
        switch CoreAISpecializationProfile(rawValue: specialization.profile) {
        case .preferGPU:
            expectedPreferredComputeUnit = "gpu"
        case .preferNeuralEngine:
            expectedPreferredComputeUnit = "neuralEngine"
        case .automatic, .cpuOnly:
            expectedPreferredComputeUnit = nil
        case nil:
            expectedPreferredComputeUnit = nil
        }
        guard specialization.preferredComputeUnit == expectedPreferredComputeUnit else {
            throw CoreAIBenchmarkEvidenceError.invalidField(
                "preferred compute unit"
            )
        }
    }

    private func validateExecutionState() throws {
        guard ["cacheHit", "cacheMiss"].contains(
            executionState.specializationCacheState
        ), executionState.functionInstanceState == "freshlyLoaded",
        executionState.inputReuseState == "generatedOnceAndReused",
        ["warmedWithExcludedRuns", "noWarmup"].contains(
            executionState.inferenceWarmupState
        ), CoreAIFunctionBenchmarkConfiguration.warmupRange.contains(
            executionState.requestedWarmupRuns
        ), CoreAIFunctionBenchmarkConfiguration.measuredRunRange.contains(
            executionState.requestedMeasuredRuns
        ) else {
            throw CoreAIBenchmarkEvidenceError.invalidField("execution state")
        }
        let expectedWarmupState = executionState.requestedWarmupRuns > 0
            ? "warmedWithExcludedRuns"
            : "noWarmup"
        guard executionState.inferenceWarmupState == expectedWarmupState else {
            throw CoreAIBenchmarkEvidenceError.invalidField(
                "inference warmup state"
            )
        }
    }

    private func validateInputs() throws {
        var names: Set<String> = []
        for input in inputs {
            try validateText(input.name, field: "input name")
            guard names.insert(input.name).inserted,
                  input.shape.allSatisfy({ $0 > 0 }),
                  CoreAIFunctionInputGenerator(rawValue: input.generator) != nil else {
                throw CoreAIBenchmarkEvidenceError.invalidField(
                    "input configuration"
                )
            }
        }
    }

    private func validateTrials(
        _ trials: [CoreAIBenchmarkEvidenceTrial],
        requestedCount: Int,
        field: String,
        allowsPartialCount: Bool
    ) throws {
        let expectedCount = allowsPartialCount ? 1...requestedCount : requestedCount...requestedCount
        let expectedIndices = trials.indices.map { $0 + 1 }
        guard expectedCount.contains(trials.count),
              trials.map(\.index) == expectedIndices else {
            throw CoreAIBenchmarkEvidenceError.invalidField(field)
        }
        for trial in trials {
            try trial.timing.validate(field: field)
        }
        if allowsPartialCount, trials.count == requestedCount {
            throw CoreAIBenchmarkEvidenceError.invalidField("stopped-early state")
        }
    }

    private func validateStatistics() throws {
        try statistics.minimum.validate(field: "minimum statistic")
        try statistics.median.validate(field: "median statistic")
        try statistics.mean.validate(field: "mean statistic")
        try statistics.maximum.validate(field: "maximum statistic")
        try statistics.standardDeviation.validate(
            field: "standard-deviation statistic"
        )
        try statistics.p95?.validate(field: "p95 statistic")
        let orderedSeconds = measuredRuns
            .map(\.timing.secondsValue)
            .sorted()
        guard let expectedMinimum = orderedSeconds.first,
              let expectedMaximum = orderedSeconds.last else {
            throw CoreAIBenchmarkEvidenceError.invalidField(
                "benchmark statistics"
            )
        }
        let sampleCount = Double(orderedSeconds.count)
        let expectedMean = orderedSeconds.reduce(0, +) / sampleCount
        let expectedMedian: Double
        if orderedSeconds.count.isMultiple(of: 2) {
            let upperIndex = orderedSeconds.count / 2
            expectedMedian = (
                orderedSeconds[upperIndex - 1] + orderedSeconds[upperIndex]
            ) / 2
        } else {
            expectedMedian = orderedSeconds[orderedSeconds.count / 2]
        }
        let expectedVariance = orderedSeconds.reduce(0) { partial, value in
            let difference = value - expectedMean
            return partial + difference * difference
        } / sampleCount
        let expectedStandardDeviation = expectedVariance.squareRoot()
        let expectedRunsPerSecond = expectedMean > 0 ? 1 / expectedMean : 0

        guard Self.approximatelyEqual(
            statistics.minimum.secondsValue,
            expectedMinimum
        ), Self.approximatelyEqual(
            statistics.median.secondsValue,
            expectedMedian
        ), Self.approximatelyEqual(
            statistics.mean.secondsValue,
            expectedMean
        ), Self.approximatelyEqual(
            statistics.maximum.secondsValue,
            expectedMaximum
        ), Self.approximatelyEqual(
            statistics.standardDeviation.secondsValue,
            expectedStandardDeviation
        ), Self.approximatelyEqual(
            statistics.runsPerSecond,
            expectedRunsPerSecond
        ) else {
            throw CoreAIBenchmarkEvidenceError.invalidField(
                "benchmark statistics"
            )
        }

        if orderedSeconds.count >= 20 {
            let nearestRankIndex = Int(ceil(0.95 * sampleCount)) - 1
            guard let p95 = statistics.p95,
                  Self.approximatelyEqual(
                    p95.secondsValue,
                    orderedSeconds[nearestRankIndex]
                  ) else {
                throw CoreAIBenchmarkEvidenceError.invalidField(
                    "p95 statistic"
                )
            }
        } else if statistics.p95 != nil {
            throw CoreAIBenchmarkEvidenceError.invalidField("p95 statistic")
        }
    }

    private func validateOutputs() throws {
        var names: Set<String> = []
        for output in outputs {
            try validateText(output.name, field: "output name")
            try validateText(output.typeDescription, field: "output type")
            guard names.insert(output.name).inserted,
                  output.shape.allSatisfy({ $0 > 0 }),
                  output.elementCount >= 0,
                  output.sampledElementCount >= 0,
                  output.sampledElementCount <= output.elementCount,
                  output.nonFiniteCount >= 0,
                  output.nonFiniteCount <= output.sampledElementCount,
                  [output.minimum, output.maximum, output.mean]
                    .compactMap({ $0 })
                    .allSatisfy(\.isFinite) else {
                throw CoreAIBenchmarkEvidenceError.invalidField(
                    "output summary"
                )
            }
            if let minimum = output.minimum,
               let maximum = output.maximum,
               minimum > maximum {
                throw CoreAIBenchmarkEvidenceError.invalidField(
                    "output numeric range"
                )
            }
        }
    }

    private func validateEnvironment() throws {
        try validateText(benchmarkEnvironment.platform, field: "platform")
        try validateText(
            benchmarkEnvironment.operatingSystem,
            field: "operating system"
        )
        try validateText(
            benchmarkEnvironment.coreAIDeviceArchitecture,
            field: "Core AI device architecture"
        )
        guard !benchmarkEnvironment.availableComputeUnits.isEmpty,
              benchmarkEnvironment.availableComputeUnits
                == benchmarkEnvironment.availableComputeUnits.sorted(),
              Set(benchmarkEnvironment.availableComputeUnits).count
                == benchmarkEnvironment.availableComputeUnits.count,
              benchmarkEnvironment.availableComputeUnits.allSatisfy({
                !$0.isEmpty
              }),
              benchmarkEnvironment.processorCount > 0,
              benchmarkEnvironment.physicalMemoryBytes > 0,
              CoreAIBuildConfiguration(
                rawValue: benchmarkEnvironment.buildConfiguration
              ) != nil,
              CoreAIThermalState(
                rawValue: benchmarkEnvironment.startedThermalState
              ) != nil,
              CoreAIThermalState(
                rawValue: benchmarkEnvironment.endedThermalState
              ) != nil,
              !benchmarkEnvironment.toolchain
                .swiftCompilerVersionConstraint.isEmpty,
              benchmarkEnvironment.toolchain.swiftLanguageMode == "6",
              [
                benchmarkEnvironment.toolchain.xcodeVersionCode,
                benchmarkEnvironment.toolchain.xcodeBuild,
                benchmarkEnvironment.toolchain.sdkName,
                benchmarkEnvironment.toolchain.sdkBuild,
                benchmarkEnvironment.toolchain.compilerIdentifier
              ].compactMap({ $0 }).allSatisfy({ !$0.isEmpty }) else {
            throw CoreAIBenchmarkEvidenceError.invalidField(
                "runtime environment"
            )
        }
    }

    private func validateMetrics() throws {
        if let peakResidentMemoryBytes = metrics.peakResidentMemoryBytes,
           peakResidentMemoryBytes == 0 {
            throw CoreAIBenchmarkEvidenceError.invalidField(
                "memory measurement"
            )
        }
        if let energyJoules = metrics.energyJoules {
            guard energyJoules.isFinite, energyJoules >= 0 else {
                throw CoreAIBenchmarkEvidenceError.invalidField(
                    "energy measurement"
                )
            }
        }
        let expectedMemoryStatus = metrics.peakResidentMemoryBytes == nil
            ? "notMeasured"
            : "measured"
        let expectedEnergyStatus = metrics.energyJoules == nil
            ? "notMeasured"
            : "measured"
        guard metrics.memoryMeasurementStatus == expectedMemoryStatus,
              metrics.energyMeasurementStatus == expectedEnergyStatus else {
            throw CoreAIBenchmarkEvidenceError.invalidField(
                "optional metric status"
            )
        }
    }

    private func validateText(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.contains("\0") else {
            throw CoreAIBenchmarkEvidenceError.invalidField(field)
        }
    }

    private static func isLowercaseHexDigit(_ character: Character) -> Bool {
        "0123456789abcdef".contains(character)
    }

    private static func approximatelyEqual(
        _ lhs: Double,
        _ rhs: Double
    ) -> Bool {
        guard lhs.isFinite, rhs.isFinite else { return false }
        let scale = max(max(abs(lhs), abs(rhs)), 1)
        return abs(lhs - rhs) <= max(1e-15, scale * 1e-12)
    }
}
