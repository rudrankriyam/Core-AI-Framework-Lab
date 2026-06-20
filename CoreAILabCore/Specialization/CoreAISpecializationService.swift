import CoreAI
import CoreVideo
import Foundation

actor CoreAISpecializationService: CoreAIFunctionRuntimeServicing {
    private var model: AIModel?
    private var modelURL: URL?
    private var configuration: CoreAISpecializationConfiguration?
    private var specializationGeneration = UUID()
    private var activeSpecializationGeneration: UUID?
    private var hasActiveRun = false

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
    ) throws -> Bool {
        try withSecurityScopedAccess(to: url) {
            try AIModelCache.default.model(
                for: url,
                options: configuration.options
            ) != nil
        }
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

        let clock = ContinuousClock()
        let startedAt = clock.now
        let cachedModel = try AIModelCache.default.model(
            for: url,
            options: configuration.options
        )
        let loadedFromCache = cachedModel != nil
        let specializedModel: AIModel
        if let cachedModel {
            specializedModel = cachedModel
        } else {
            specializedModel = try await AIModel.specialize(
                contentsOf: url,
                options: configuration.options,
                cache: .default,
                cachePolicy: cachePolicy.policy
            )
        }

        guard specializationGeneration == generation else {
            throw CancellationError()
        }
        model = specializedModel
        modelURL = url
        self.configuration = configuration
        return CoreAISpecializationResult(
            configuration: configuration,
            duration: startedAt.duration(to: clock.now),
            loadedFromCache: loadedFromCache,
            functionNames: specializedModel.functionNames.sorted(),
            bookmarkData: specializedModel.bookmarkData
        )
    }

    func removeCachedEntry(
        at url: URL,
        configuration: CoreAISpecializationConfiguration
    ) throws {
        guard !hasActiveRun else {
            throw CoreAIFunctionWorkbenchError.functionAlreadyRunning
        }
        specializationGeneration = UUID()
        activeSpecializationGeneration = nil
        releaseLoadedModel(ifMatching: url, configuration: configuration)
        try withSecurityScopedAccess(to: url) {
            try AIModelCache.default.deleteEntry(
                for: url,
                options: configuration.options
            )
        }
    }

    func removeCachedEntries(at url: URL) throws {
        guard !hasActiveRun else {
            throw CoreAIFunctionWorkbenchError.functionAlreadyRunning
        }
        specializationGeneration = UUID()
        activeSpecializationGeneration = nil
        if modelURL == url {
            reset()
        }
        try withSecurityScopedAccess(to: url) {
            try AIModelCache.default.deleteEntries(for: url)
        }
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
        for index in 0..<benchmarkConfiguration.measuredRuns {
            try Task.checkCancellation()
            let startedAt = clock.now
            var rawOutputs = try await function.run(inputs: inputs)
            let duration = startedAt.duration(to: clock.now)
            try Task.checkCancellation()
            trials.append(CoreAIBenchmarkTrial(index: index + 1, duration: duration))
            if index == benchmarkConfiguration.measuredRuns - 1 {
                summaries = try summarizeOutputs(
                    &rawOutputs,
                    descriptor: descriptor
                )
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
