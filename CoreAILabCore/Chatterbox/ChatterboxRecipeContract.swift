import Foundation

enum ChatterboxEntrypointRole: String, Sendable {
    case decode
    case generateMel
    case prefill
    case synthesizeWaveform
}

struct ChatterboxResolvedStage: Sendable {
    let stage: ChatterboxPipelineStage
    let manifest: CoreAIRecipePipelineStageManifest
    let artifact: CoreAIArtifactManifest

    var requiredFunctionNames: Set<String> {
        Set(manifest.entrypoints.values)
    }

    func entrypoint(for role: ChatterboxEntrypointRole) throws -> String {
        guard let name = manifest.entrypoints[role.rawValue] else {
            throw CoreAIManifestValidationError.missingValue(
                path: "pipeline.stages.\(stage.rawValue).entrypoints.\(role.rawValue)"
            )
        }
        return name
    }
}

struct ChatterboxResolvedCapacity: Sendable, Equatable {
    let maximumTextTokens: Int
    let maximumSpeechTokens: Int
    let maximumContextLength: Int
    let requiresStopToken: Bool
    let t3LayerCount: Int
    let t3HeadCount: Int
    let t3HeadDimension: Int
    let t3StartSpeechToken: Int
    let t3StopSpeechToken: Int
    let speechTokenBufferCount: Int
    let endSilenceTokenCount: Int
    let silenceToken: Int
    let melNoiseFrameCount: Int
    let generatedMelFrameCount: Int
    let melFramesPerSpeechToken: Int
    let sourceChannelCount: Int
    let samplesPerMelFrame: Int
    let sampleRate: Int

    init(manifest: CoreAICapacityManifest) throws {
        try manifest.validate()
        guard let maximumTextTokens = manifest.maximumInputTokens else {
            throw CoreAIManifestValidationError.missingValue(
                path: "capacity.maximumInputTokens"
            )
        }
        guard let maximumSpeechTokens = manifest.maximumGeneratedTokens else {
            throw CoreAIManifestValidationError.missingValue(
                path: "capacity.maximumGeneratedTokens"
            )
        }
        guard let maximumContextLength = manifest.maximumContextTokens else {
            throw CoreAIManifestValidationError.missingValue(
                path: "capacity.maximumContextTokens"
            )
        }

        self.maximumTextTokens = maximumTextTokens
        self.maximumSpeechTokens = maximumSpeechTokens
        self.maximumContextLength = maximumContextLength
        requiresStopToken = manifest.requiresStopSignal
        t3LayerCount = try manifest.requiredParameter(named: "t3LayerCount")
        t3HeadCount = try manifest.requiredParameter(named: "t3HeadCount")
        t3HeadDimension = try manifest.requiredParameter(named: "t3HeadDimension")
        t3StartSpeechToken = try manifest.requiredParameter(named: "t3StartSpeechToken")
        t3StopSpeechToken = try manifest.requiredParameter(named: "t3StopSpeechToken")
        speechTokenBufferCount = try manifest.requiredParameter(
            named: "speechTokenBufferCount"
        )
        endSilenceTokenCount = try manifest.requiredParameter(
            named: "endSilenceTokenCount"
        )
        silenceToken = try manifest.requiredParameter(named: "silenceToken")
        melNoiseFrameCount = try manifest.requiredParameter(named: "melNoiseFrameCount")
        generatedMelFrameCount = try manifest.requiredParameter(
            named: "generatedMelFrameCount"
        )
        melFramesPerSpeechToken = try manifest.requiredParameter(
            named: "melFramesPerSpeechToken"
        )
        sourceChannelCount = try manifest.requiredParameter(named: "sourceChannelCount")
        samplesPerMelFrame = try manifest.requiredParameter(named: "samplesPerMelFrame")
        sampleRate = try manifest.requiredParameter(named: "sampleRate")

        let boundedValues: [(String, Int, ClosedRange<Int>)] = [
            ("maximumInputTokens", maximumTextTokens, 1...4_096),
            ("maximumGeneratedTokens", maximumSpeechTokens, 1...4_096),
            ("maximumContextTokens", maximumContextLength, 2...8_192),
            ("t3LayerCount", t3LayerCount, 1...256),
            ("t3HeadCount", t3HeadCount, 1...256),
            ("t3HeadDimension", t3HeadDimension, 1...4_096),
            ("t3StartSpeechToken", t3StartSpeechToken, 0...Int(Int32.max)),
            ("t3StopSpeechToken", t3StopSpeechToken, 0...Int(Int32.max)),
            ("speechTokenBufferCount", speechTokenBufferCount, 1...8_192),
            ("endSilenceTokenCount", endSilenceTokenCount, 0...8_192),
            ("silenceToken", silenceToken, 0...Int(Int32.max)),
            ("melNoiseFrameCount", melNoiseFrameCount, 1...65_536),
            ("generatedMelFrameCount", generatedMelFrameCount, 1...65_536),
            ("melFramesPerSpeechToken", melFramesPerSpeechToken, 1...1_024),
            ("sourceChannelCount", sourceChannelCount, 1...1_024),
            ("samplesPerMelFrame", samplesPerMelFrame, 1...65_536),
            ("sampleRate", sampleRate, 8_000...384_000),
        ]
        for (name, value, range) in boundedValues {
            try Self.require(value, in: range, named: name)
        }

        let bufferedSpeechTokens = try Self.safeSum(
            maximumSpeechTokens,
            endSilenceTokenCount,
            path: "capacity.maximumGeneratedTokens"
        )
        guard bufferedSpeechTokens <= speechTokenBufferCount else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "capacity.maximumGeneratedTokens",
                reason: "generated tokens plus end silence exceed the speech-token buffer"
            )
        }
        guard maximumSpeechTokens < maximumContextLength else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "capacity.maximumGeneratedTokens",
                reason: "it must be lower than maximumContextTokens"
            )
        }
        let expectedMelFrames = try Self.safeProduct(
            [speechTokenBufferCount, melFramesPerSpeechToken],
            maximum: 65_536,
            path: "capacity.parameters.generatedMelFrameCount"
        )
        guard generatedMelFrameCount == expectedMelFrames else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "capacity.parameters.generatedMelFrameCount",
                reason: "it must match buffered speech tokens times mel frames per token"
            )
        }
        _ = try Self.safeProduct(
            [t3LayerCount, t3HeadCount, maximumContextLength, t3HeadDimension],
            maximum: 100_000_000,
            path: "capacity.parameters.t3CacheShape"
        )
        _ = try Self.safeProduct(
            [80, melNoiseFrameCount],
            maximum: 5_000_000,
            path: "capacity.parameters.melNoiseFrameCount"
        )
        _ = try Self.safeProduct(
            [sourceChannelCount, generatedMelFrameCount, samplesPerMelFrame],
            maximum: 50_000_000,
            path: "capacity.parameters.vocoderNoiseShape"
        )
        _ = try Self.safeProduct(
            [sampleRate, 2],
            maximum: Int(UInt32.max),
            path: "capacity.parameters.sampleRate"
        )
    }

    private static func require(
        _ value: Int,
        in range: ClosedRange<Int>,
        named name: String
    ) throws {
        guard range.contains(value) else {
            let path = name.hasPrefix("maximum")
                ? "capacity.\(name)"
                : "capacity.parameters.\(name)"
            throw CoreAIManifestValidationError.invalidValue(
                path: path,
                reason: "it must be between \(range.lowerBound) and \(range.upperBound)"
            )
        }
    }

    private static func safeSum(_ lhs: Int, _ rhs: Int, path: String) throws -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw CoreAIManifestValidationError.invalidValue(
                path: path,
                reason: "the configured values overflow the runtime integer range"
            )
        }
        return result
    }

    private static func safeProduct(
        _ values: [Int],
        maximum: Int,
        path: String
    ) throws -> Int {
        var product = 1
        for value in values {
            let (next, overflow) = product.multipliedReportingOverflow(by: value)
            guard !overflow, next <= maximum else {
                throw CoreAIManifestValidationError.invalidValue(
                    path: path,
                    reason: "the configured shape exceeds the safe runtime capacity"
                )
            }
            product = next
        }
        return product
    }
}

struct ChatterboxRecipeContract: Sendable {
    let manifest: CoreAIRecipeManifest
    let target: CoreAITargetManifest
    let tokenizerArtifact: CoreAIArtifactManifest
    let capacity: ChatterboxResolvedCapacity
    private let stagesByID: [ChatterboxPipelineStage: ChatterboxResolvedStage]

    init(manifest: CoreAIRecipeManifest) throws {
        try manifest.validate()
        guard manifest.pipeline.experience == .textToSpeech else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "pipeline.experience",
                reason: "Chatterbox requires the textToSpeech experience"
            )
        }
        guard let target = manifest.defaultTarget else {
            throw CoreAIManifestValidationError.unknownReference(
                path: "recipe.defaultTargetID",
                identifier: manifest.defaultTargetID
            )
        }
        guard let tokenizerID = manifest.pipeline.tokenizerArtifactID,
              let tokenizerArtifact = manifest.artifact(id: tokenizerID) else {
            throw CoreAIManifestValidationError.missingValue(
                path: "pipeline.tokenizerArtifactID"
            )
        }

        var resolvedStages = [ChatterboxPipelineStage: ChatterboxResolvedStage]()
        for stageManifest in manifest.pipeline.stages {
            guard let stage = ChatterboxPipelineStage(rawValue: stageManifest.id) else {
                throw CoreAIManifestValidationError.invalidValue(
                    path: "pipeline.stages.\(stageManifest.id).id",
                    reason: "the stage is not supported by the Chatterbox runtime adapter"
                )
            }
            guard let artifact = manifest.artifact(id: stageManifest.artifactID) else {
                throw CoreAIManifestValidationError.unknownReference(
                    path: "pipeline.stages.\(stageManifest.id).artifactID",
                    identifier: stageManifest.artifactID
                )
            }
            resolvedStages[stage] = ChatterboxResolvedStage(
                stage: stage,
                manifest: stageManifest,
                artifact: artifact
            )
        }
        let missingStages = Set(ChatterboxPipelineStage.allCases)
            .subtracting(resolvedStages.keys)
        guard missingStages.isEmpty else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "pipeline.stages",
                reason: "missing Chatterbox stages: \(missingStages.map(\.rawValue).sorted().joined(separator: ", "))"
            )
        }

        self.manifest = manifest
        self.target = target
        self.tokenizerArtifact = tokenizerArtifact
        capacity = try ChatterboxResolvedCapacity(manifest: manifest.capacity)
        stagesByID = resolvedStages
        try validateEntrypointRoles()
    }

    func resolvedStage(_ stage: ChatterboxPipelineStage) throws -> ChatterboxResolvedStage {
        guard let resolved = stagesByID[stage] else {
            throw CoreAIManifestValidationError.missingValue(
                path: "pipeline.stages.\(stage.rawValue)"
            )
        }
        return resolved
    }

    private func validateEntrypointRoles() throws {
        for stage in [ChatterboxPipelineStage.t3Embeddings, .t3Transformer] {
            try validateEntrypointRoles([.prefill, .decode], for: stage)
        }
        try validateEntrypointRoles([.generateMel], for: .s3gen)
        try validateEntrypointRoles([.synthesizeWaveform], for: .vocoder)
    }

    private func validateEntrypointRoles(
        _ expectedRoles: Set<ChatterboxEntrypointRole>,
        for stage: ChatterboxPipelineStage
    ) throws {
        let resolved = try resolvedStage(stage)
        let expectedKeys = Set(expectedRoles.map(\.rawValue))
        let actualKeys = Set(resolved.manifest.entrypoints.keys)
        guard actualKeys == expectedKeys else {
            throw CoreAIManifestValidationError.invalidValue(
                path: "pipeline.stages.\(stage.rawValue).entrypoints",
                reason: "expected exactly these roles: \(expectedKeys.sorted().joined(separator: ", "))"
            )
        }
        for role in expectedRoles {
            _ = try resolved.entrypoint(for: role)
        }
    }
}
