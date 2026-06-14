import CoreAI
import Foundation
import Tokenizers

actor ChatterboxCoreAIEngine {
    private enum Constants {
        static let t3LayerCount = 24
        static let t3HeadCount = 16
        static let t3HeadDimension = 64
        static let t3MaximumContextLength = 768
        static let t3MaximumTextTokens = 256
        static let t3StartSpeechToken = 6_561
        static let t3StopSpeechToken = 6_562

        static let s3GeneratedTokenCount = 256
        static let s3EndSilenceTokenCount = 3
        static let s3SilenceToken = 4_299
        static let s3TotalMelFrames = 1_012

        static let sourceChannelCount = 9
        static let samplesPerMelFrame = 480
    }

    private struct BundledResources: Sendable {
        let rootURL: URL
        let tokenizerURL: URL
        let assetURLs: [ChatterboxPipelineStage: URL]

        init(bundle: Bundle) throws {
            guard let rootURL = bundle.url(
                forResource: "Chatterbox",
                withExtension: nil
            ) else {
                throw ChatterboxCoreAIError.bundledResourcesMissing
            }

            var assetURLs = [ChatterboxPipelineStage: URL]()
            for stage in ChatterboxPipelineStage.allCases {
                let url = rootURL.appending(
                    path: stage.assetFilename,
                    directoryHint: .isDirectory
                )
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ChatterboxCoreAIError.bundledResourcesMissing
                }
                assetURLs[stage] = url
            }

            let tokenizerURL = rootURL.appending(
                path: "tokenizer",
                directoryHint: .isDirectory
            )
            guard FileManager.default.fileExists(atPath: tokenizerURL.path) else {
                throw ChatterboxCoreAIError.bundledResourcesMissing
            }

            self.rootURL = rootURL
            self.tokenizerURL = tokenizerURL
            self.assetURLs = assetURLs
        }

        func assetURL(for stage: ChatterboxPipelineStage) throws -> URL {
            guard let url = assetURLs[stage] else {
                throw ChatterboxCoreAIError.bundledResourcesMissing
            }
            return url
        }
    }

    private struct SpeechTokenGeneration: Sendable {
        let tokens: [Int]
        let reachedStopToken: Bool
        let setupTime: TimeInterval
        let prefillTime: TimeInterval
        let embeddingInferenceTime: TimeInterval
        let transformerInferenceTime: TimeInterval
        let decodeInferenceTime: TimeInterval
        let decodeHostTime: TimeInterval
    }

    private struct MelGeneration: Sendable {
        let mel: NDArray
        let setupTime: TimeInterval
        let noiseTime: TimeInterval
        let inferenceTime: TimeInterval
    }

    private struct WaveformGeneration: Sendable {
        let waveform: [Float]
        let setupTime: TimeInterval
        let noiseTime: TimeInterval
        let inferenceTime: TimeInterval
    }

    private struct PreparedPipeline: Sendable {
        let embeddingPrefill: InferenceFunction
        let embeddingDecode: InferenceFunction
        let transformerPrefill: InferenceFunction
        let transformerDecode: InferenceFunction
        let s3GenURL: URL
        let vocoderURL: URL
    }

    private let bundle: Bundle
    private let fileManager = FileManager.default
    private var tokenizer: (any Tokenizer)?
    private var pipeline: PreparedPipeline?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func prepareBundledModels() async throws -> ChatterboxModelInspection {
        let resources = try BundledResources(bundle: bundle)
        let tokenizer = try await AutoTokenizer.from(
            modelFolder: resources.tokenizerURL
        )
        try validateTokenizer(tokenizer)

        let options = specializationOptions
        var assets = [ChatterboxAssetInspection]()
        var functionNamesByStage = [
            ChatterboxPipelineStage: Set<String>
        ]()
        var models = [ChatterboxPipelineStage: AIModel]()
        var author = ""
        var license = ""

        for stage in ChatterboxPipelineStage.allCases {
            let url = try resources.assetURL(for: stage)
            guard AIModelAsset.isValid(at: url) else {
                throw ChatterboxCoreAIError.invalidModelAsset(stage.assetFilename)
            }

            let asset = try AIModelAsset(contentsOf: url)
            let model = try await AIModel.specialize(
                contentsOf: url,
                options: options,
                cache: .default,
                cachePolicy: .persistent
            )
            let functionNames = model.functionNames.sorted()
            let functionNameSet = Set(functionNames)
            let missingFunctions = stage.requiredFunctionNames
                .subtracting(functionNameSet)
                .sorted()
            guard missingFunctions.isEmpty else {
                throw ChatterboxCoreAIError.missingEntrypoints(
                    asset: stage.assetFilename,
                    names: missingFunctions
                )
            }

            functionNamesByStage[stage] = functionNameSet
            models[stage] = model
            assets.append(
                ChatterboxAssetInspection(
                    stage: stage,
                    sourceURL: url,
                    functionNames: functionNames,
                    sizeInBytes: try allocatedSize(of: url)
                )
            )
            if author.isEmpty {
                author = asset.metadata.author
            }
            if license.isEmpty {
                license = asset.metadata.license
            }
        }

        guard let embeddingsModel = models[.t3Embeddings],
              let transformerModel = models[.t3Transformer],
              let s3GenModel = models[.s3gen],
              let vocoderModel = models[.vocoder]
        else {
            throw ChatterboxCoreAIError.bundledResourcesMissing
        }
        self.pipeline = PreparedPipeline(
            embeddingPrefill: try loadFunction(
                "prefill",
                from: embeddingsModel
            ),
            embeddingDecode: try loadFunction(
                "decode",
                from: embeddingsModel
            ),
            transformerPrefill: try loadFunction(
                "prefill",
                from: transformerModel
            ),
            transformerDecode: try loadFunction(
                "decode",
                from: transformerModel
            ),
            s3GenURL: try resources.assetURL(for: .s3gen),
            vocoderURL: try resources.assetURL(for: .vocoder)
        )
        _ = s3GenModel
        _ = vocoderModel
        self.tokenizer = tokenizer

        return ChatterboxModelInspection(
            assets: assets,
            author: author,
            license: license,
            deviceArchitectureName: AIModel.deviceArchitectureName,
            contractValidation: ChatterboxFunctionContract.validate(
                functionNamesByStage: functionNamesByStage
            )
        )
    }

    func synthesize(
        _ request: ChatterboxGenerationRequest
    ) async throws -> ChatterboxGenerationResult {
        guard let pipeline, let tokenizer else {
            throw ChatterboxCoreAIError.modelNotLoaded
        }

        let trimmedText = request.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedText.isEmpty else {
            throw ChatterboxCoreAIError.emptyPrompt
        }

        let startedAt = ContinuousClock.now
        let textPreparationStartedAt = ContinuousClock.now
        let normalizedText = ChatterboxTextNormalizer.normalize(trimmedText)
        let textTokens = tokenizer.encode(text: normalizedText)
        guard textTokens.count <= Constants.t3MaximumTextTokens else {
            throw ChatterboxCoreAIError.textTooLong(textTokens.count)
        }
        let textPreparationTime = textPreparationStartedAt.duration(
            to: .now
        ).timeInterval

        let maximumGeneratedTokens = min(
            max(request.maximumGeneratedTokens, 1),
            Constants.s3GeneratedTokenCount - 3
        )
        let random = ChatterboxRandomGenerator(seed: request.seed)
        let generation = try await generateSpeechTokens(
            pipeline: pipeline,
            textTokens: textTokens.map(Int32.init),
            maximumGeneratedTokens: maximumGeneratedTokens,
            random: random
        )
        guard generation.reachedStopToken else {
            throw ChatterboxCoreAIError.generationLimitReached
        }
        let speechTokens = generation.tokens
        let melGeneration = try await generateMel(
            modelURL: pipeline.s3GenURL,
            speechTokens: speechTokens,
            random: random
        )
        let waveformGeneration = try await generateWaveform(
            modelURL: pipeline.vocoderURL,
            mel: melGeneration.mel,
            random: random
        )
        let audioPostprocessingStartedAt = ContinuousClock.now
        let fullWaveform = waveformGeneration.waveform
        let outputSampleCount = min(
            fullWaveform.count,
            (speechTokens.count + Constants.s3EndSilenceTokenCount)
                * 2
                * Constants.samplesPerMelFrame
        )
        let waveform = Array(fullWaveform.prefix(outputSampleCount))

        let outputURL = URL.temporaryDirectory
            .appending(path: "chatterbox-coreai-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        try ChatterboxWaveFile.write(samples: waveform, to: outputURL)
        let audioPostprocessingTime = audioPostprocessingStartedAt.duration(
            to: .now
        ).timeInterval
        let elapsedTime = startedAt.duration(to: .now).timeInterval

        return ChatterboxGenerationResult(
            audioURL: outputURL,
            normalizedText: normalizedText,
            generatedTokenCount: speechTokens.count,
            audioDuration: Double(waveform.count)
                / Double(ChatterboxWaveFile.sampleRate),
            elapsedTime: elapsedTime,
            metrics: ChatterboxGenerationMetrics(
                textPreparation: textPreparationTime,
                t3Setup: generation.setupTime,
                t3Prefill: generation.prefillTime,
                t3EmbeddingInference: generation.embeddingInferenceTime,
                t3TransformerInference: generation.transformerInferenceTime,
                t3DecodeInference: generation.decodeInferenceTime,
                t3DecodeHost: generation.decodeHostTime,
                s3GenSetup: melGeneration.setupTime,
                s3GenNoise: melGeneration.noiseTime,
                s3GenInference: melGeneration.inferenceTime,
                vocoderSetup: waveformGeneration.setupTime,
                vocoderNoise: waveformGeneration.noiseTime,
                vocoderInference: waveformGeneration.inferenceTime,
                audioPostprocessing: audioPostprocessingTime
            )
        )
    }

    private var specializationOptions: SpecializationOptions {
        let availableKinds = ComputeUnitKind.availableKinds
        let override = ProcessInfo.processInfo.environment[
            "CHATTERBOX_COMPUTE_UNIT"
        ]
        let preferredKind: ComputeUnitKind
        switch override {
        case "neuralEngine" where availableKinds.contains(.neuralEngine):
            preferredKind = .neuralEngine
        case "cpu" where availableKinds.contains(.cpu):
            preferredKind = .cpu
        default:
            preferredKind = availableKinds.contains(.gpu) ? .gpu : .cpu
        }
        return SpecializationOptions(preferredComputeUnitKind: preferredKind)
    }

    private func loadModel(at url: URL) async throws -> AIModel {
        let options = specializationOptions
        if let cached = try AIModelCache.default.model(
            for: url,
            options: options
        ) {
            return cached
        }
        return try await AIModel.specialize(
            contentsOf: url,
            options: options,
            cache: .default,
            cachePolicy: .persistent
        )
    }

    private func generateSpeechTokens(
        pipeline: PreparedPipeline,
        textTokens: [Int32],
        maximumGeneratedTokens: Int,
        random: ChatterboxRandomGenerator
    ) async throws -> SpeechTokenGeneration {
        let setupStartedAt = ContinuousClock.now
        let embeddingPrefill = pipeline.embeddingPrefill
        let embeddingDecode = pipeline.embeddingDecode
        let transformerPrefill = pipeline.transformerPrefill
        let transformerDecode = pipeline.transformerDecode
        let setupTime = setupStartedAt.duration(to: .now).timeInterval

        let prefillStartedAt = ContinuousClock.now
        var embeddingOutputs = try await embeddingPrefill.run(
            inputs: [
                "textTokens": NDArray(
                    scalars: textTokens,
                    shape: [1, textTokens.count]
                )
            ]
        )
        guard let inputEmbeddings = embeddingOutputs
            .remove("inputEmbeddings")?.ndArray
        else {
            throw ChatterboxCoreAIError.missingOutput("inputEmbeddings")
        }

        var sequenceLength = inputEmbeddings.shape[1]
        let availableGeneratedTokens = Constants.t3MaximumContextLength
            - sequenceLength
            - 1
        let generationBudget = min(
            maximumGeneratedTokens,
            availableGeneratedTokens
        )
        guard generationBudget > 0 else {
            throw ChatterboxCoreAIError.textTooLong(textTokens.count)
        }

        let cacheShape = [
            Constants.t3LayerCount,
            1,
            Constants.t3HeadCount,
            Constants.t3MaximumContextLength,
            Constants.t3HeadDimension,
        ]
        var keyCache = ChatterboxNDArray.zerosFloat16(shape: cacheShape)
        var valueCache = ChatterboxNDArray.zerosFloat16(shape: cacheShape)
        let positionIDs = (0..<sequenceLength).map(Int32.init)

        var transformerOutputs = try await transformerPrefill.run(
            inputs: [
                "inputEmbeddings": inputEmbeddings,
                "positionIDs": NDArray(
                    scalars: positionIDs,
                    shape: [1, sequenceLength]
                ),
                "keyCache": keyCache,
                "valueCache": valueCache,
            ]
        )
        let prefillResult = try takeTransformerOutputs(
            from: &transformerOutputs
        )
        try ChatterboxNDArray.patchCache(
            &keyCache,
            with: prefillResult.keyUpdates,
            at: 0
        )
        try ChatterboxNDArray.patchCache(
            &valueCache,
            with: prefillResult.valueUpdates,
            at: 0
        )

        var generatedTokens = [Int]()
        var token = try ChatterboxSampler.sample(
            logits: ChatterboxNDArray.lastLogits(from: prefillResult.logits),
            generatedTokens: [Constants.t3StartSpeechToken],
            random: random
        )
        let prefillTime = prefillStartedAt.duration(to: .now).timeInterval
        if token == Constants.t3StopSpeechToken {
            return SpeechTokenGeneration(
                tokens: [],
                reachedStopToken: true,
                setupTime: setupTime,
                prefillTime: prefillTime,
                embeddingInferenceTime: 0,
                transformerInferenceTime: 0,
                decodeInferenceTime: 0,
                decodeHostTime: 0
            )
        }
        generatedTokens.append(token)

        var embeddingInferenceTime: TimeInterval = 0
        var transformerInferenceTime: TimeInterval = 0
        var decodeHostTime: TimeInterval = 0
        for _ in 1..<generationBudget {
            let embeddingInferenceStartedAt = ContinuousClock.now
            var decodeEmbeddingOutputs = try await embeddingDecode.run(
                inputs: [
                    "speechToken": NDArray(
                        scalars: [Int32(token)],
                        shape: [1, 1]
                    )
                ]
            )
            guard let decodeEmbedding = decodeEmbeddingOutputs
                .remove("inputEmbeddings")?.ndArray
            else {
                throw ChatterboxCoreAIError.missingOutput("inputEmbeddings")
            }
            embeddingInferenceTime += embeddingInferenceStartedAt.duration(
                to: .now
            ).timeInterval

            sequenceLength += 1
            let transformerInferenceStartedAt = ContinuousClock.now
            var decodeOutputs = try await transformerDecode.run(
                inputs: [
                    "inputEmbeddings": decodeEmbedding,
                    "positionIDs": NDArray(
                        scalars: [Int32(sequenceLength - 1)],
                        shape: [1, 1]
                    ),
                    "keyCache": keyCache,
                    "valueCache": valueCache,
                ]
            )
            let decodeResult = try takeTransformerOutputs(
                from: &decodeOutputs
            )
            transformerInferenceTime += transformerInferenceStartedAt.duration(
                to: .now
            ).timeInterval

            let decodeHostStartedAt = ContinuousClock.now
            let cacheOffset = sequenceLength - 1
            try ChatterboxNDArray.patchCache(
                &keyCache,
                with: decodeResult.keyUpdates,
                at: cacheOffset
            )
            try ChatterboxNDArray.patchCache(
                &valueCache,
                with: decodeResult.valueUpdates,
                at: cacheOffset
            )
            token = try ChatterboxSampler.sample(
                logits: ChatterboxNDArray.lastLogits(
                    from: decodeResult.logits
                ),
                generatedTokens: generatedTokens,
                random: random
            )
            decodeHostTime += decodeHostStartedAt.duration(
                to: .now
            ).timeInterval
            if token == Constants.t3StopSpeechToken {
                return SpeechTokenGeneration(
                    tokens: generatedTokens,
                    reachedStopToken: true,
                    setupTime: setupTime,
                    prefillTime: prefillTime,
                    embeddingInferenceTime: embeddingInferenceTime,
                    transformerInferenceTime: transformerInferenceTime,
                    decodeInferenceTime: embeddingInferenceTime
                        + transformerInferenceTime,
                    decodeHostTime: decodeHostTime
                )
            }
            generatedTokens.append(token)
        }

        return SpeechTokenGeneration(
            tokens: generatedTokens,
            reachedStopToken: false,
            setupTime: setupTime,
            prefillTime: prefillTime,
            embeddingInferenceTime: embeddingInferenceTime,
            transformerInferenceTime: transformerInferenceTime,
            decodeInferenceTime: embeddingInferenceTime
                + transformerInferenceTime,
            decodeHostTime: decodeHostTime
        )
    }

    private func generateMel(
        modelURL: URL,
        speechTokens: [Int],
        random: ChatterboxRandomGenerator
    ) async throws -> MelGeneration {
        var paddedTokens = [Int32](
            repeating: Int32(Constants.s3SilenceToken),
            count: Constants.s3GeneratedTokenCount
        )
        let validTokens = speechTokens
            .filter { $0 < Constants.t3StartSpeechToken }
            .prefix(
                Constants.s3GeneratedTokenCount
                    - Constants.s3EndSilenceTokenCount
            )
        for (index, token) in validTokens.enumerated() {
            paddedTokens[index] = Int32(token)
        }

        let noiseStartedAt = ContinuousClock.now
        let noiseCount = 80 * Constants.s3TotalMelFrames
        let noise = (0..<noiseCount).map { _ in
            Float16(random.nextNormal())
        }
        let noiseTime = noiseStartedAt.duration(to: .now).timeInterval
        let setupStartedAt = ContinuousClock.now
        let model = try await loadModel(at: modelURL)
        let function = try loadFunction("main", from: model)
        let setupTime = setupStartedAt.duration(to: .now).timeInterval
        let inferenceStartedAt = ContinuousClock.now
        var outputs = try await function.run(
            inputs: [
                "speechTokens": NDArray(
                    scalars: paddedTokens,
                    shape: [1, Constants.s3GeneratedTokenCount]
                ),
                "noise": NDArray(
                    scalars: noise,
                    shape: [1, 80, Constants.s3TotalMelFrames]
                ),
            ]
        )
        guard let mel = outputs.remove("mel")?.ndArray else {
            throw ChatterboxCoreAIError.missingOutput("mel")
        }
        return MelGeneration(
            mel: mel,
            setupTime: setupTime,
            noiseTime: noiseTime,
            inferenceTime: inferenceStartedAt.duration(to: .now).timeInterval
        )
    }

    private func generateWaveform(
        modelURL: URL,
        mel: NDArray,
        random: ChatterboxRandomGenerator
    ) async throws -> WaveformGeneration {
        guard let melFrameCount = mel.shape.last, melFrameCount > 0 else {
            throw ChatterboxCoreAIError.invalidOutputShape(
                "S3Gen returned an empty mel spectrogram."
            )
        }

        let noiseStartedAt = ContinuousClock.now
        var phase = [Float16](
            repeating: 0,
            count: Constants.sourceChannelCount
        )
        for channel in 1..<Constants.sourceChannelCount {
            phase[channel] = Float16(
                (random.nextUnitDouble() * 2 - 1) * Double.pi
            )
        }

        let sampleCount = melFrameCount * Constants.samplesPerMelFrame
        let noiseCount = Constants.sourceChannelCount * sampleCount
        let noise = (0..<noiseCount).map { _ in
            Float16(random.nextNormal())
        }
        let noiseTime = noiseStartedAt.duration(to: .now).timeInterval
        let setupStartedAt = ContinuousClock.now
        let model = try await loadModel(at: modelURL)
        let function = try loadFunction("vocoder", from: model)
        let setupTime = setupStartedAt.duration(to: .now).timeInterval
        let inferenceStartedAt = ContinuousClock.now
        var outputs = try await function.run(
            inputs: [
                "speech_feat": mel,
                "phase": NDArray(
                    scalars: phase,
                    shape: [1, Constants.sourceChannelCount, 1]
                ),
                "noise": NDArray(
                    scalars: noise,
                    shape: [
                        1,
                        Constants.sourceChannelCount,
                        sampleCount,
                    ]
                ),
            ]
        )
        guard let waveform = outputs.remove("waveform")?.ndArray else {
            throw ChatterboxCoreAIError.missingOutput("waveform")
        }
        return WaveformGeneration(
            waveform: try ChatterboxNDArray.floats(from: waveform),
            setupTime: setupTime,
            noiseTime: noiseTime,
            inferenceTime: inferenceStartedAt.duration(to: .now).timeInterval
        )
    }

    private func loadFunction(
        _ name: String,
        from model: AIModel
    ) throws -> InferenceFunction {
        guard let function = try model.loadFunction(named: name) else {
            throw ChatterboxCoreAIError.missingFunction(name)
        }
        return function
    }

    private func takeTransformerOutputs(
        from outputs: inout InferenceFunction.Outputs
    ) throws -> (
        logits: NDArray,
        keyUpdates: NDArray,
        valueUpdates: NDArray
    ) {
        guard let logits = outputs.remove("logits")?.ndArray else {
            throw ChatterboxCoreAIError.missingOutput("logits")
        }
        guard let keyUpdates = outputs.remove("keyUpdates")?.ndArray else {
            throw ChatterboxCoreAIError.missingOutput("keyUpdates")
        }
        guard let valueUpdates = outputs.remove("valueUpdates")?.ndArray else {
            throw ChatterboxCoreAIError.missingOutput("valueUpdates")
        }
        return (logits, keyUpdates, valueUpdates)
    }

    private func validateTokenizer(_ tokenizer: any Tokenizer) throws {
        let parityText = "This voice is running entirely on my Mac with Core AI. [chuckle] No cloud, no MLX, just Chatterbox."
        let expectedTokens = [
            1_212, 3_809, 318, 2_491, 5_000, 319, 616, 4_100, 351,
            7_231, 9_552, 13, 220, 50_274, 1_400, 6_279, 11, 645,
            10_373, 55, 11, 655, 609, 1_436, 3_524, 13,
        ]
        guard tokenizer.encode(text: parityText) == expectedTokens else {
            throw ChatterboxCoreAIError.tokenizerParityFailed
        }
    }

    private func allocatedSize(of url: URL) throws -> Int64 {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else {
                continue
            }
            total += Int64(
                values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? values.fileSize
                    ?? 0
            )
        }
        return total
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
