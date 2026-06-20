import CoreAI
import CoreVideo
import Foundation

actor CoreAISpecializationService: CoreAIFunctionRuntimeServicing {
    private var model: AIModel?
    private var modelURL: URL?
    private var profile: CoreAISpecializationProfile?
    private var specializationGeneration = UUID()
    private var hasActiveRun = false

    func reset() {
        guard !hasActiveRun else { return }
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
        guard !hasActiveRun else {
            throw CoreAIFunctionWorkbenchError.functionAlreadyRunning
        }
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
        guard !hasActiveRun else {
            throw CoreAIFunctionWorkbenchError.functionAlreadyRunning
        }
        specializationGeneration = UUID()
        releaseLoadedModel(ifMatching: url, profile: profile)
        try withSecurityScopedAccess(to: url) {
            try AIModelCache.default.deleteEntry(for: url, options: profile.options)
        }
    }

    func removeCachedEntries(at url: URL) throws {
        guard !hasActiveRun else {
            throw CoreAIFunctionWorkbenchError.functionAlreadyRunning
        }
        specializationGeneration = UUID()
        if modelURL == url {
            reset()
        }
        try withSecurityScopedAccess(to: url) {
            try AIModelCache.default.deleteEntries(for: url)
        }
    }

    func functionContracts() throws -> [CoreAIFunctionContract] {
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
        guard let function = try model.loadFunction(named: functionName) else {
            throw CoreAIFunctionWorkbenchError.functionUnavailable(functionName)
        }

        hasActiveRun = true
        defer { hasActiveRun = false }

        let descriptor = function.descriptor
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

        let clock = ContinuousClock()
        let startedAt = clock.now
        var rawOutputs = try await function.run(inputs: inputs)
        let duration = startedAt.duration(to: clock.now)
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
        return CoreAIFunctionRunResult(
            functionName: functionName,
            duration: duration,
            outputs: summaries
        )
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
