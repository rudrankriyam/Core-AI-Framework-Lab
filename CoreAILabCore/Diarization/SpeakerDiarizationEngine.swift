import Foundation

actor SpeakerDiarizationEngine: SpeakerDiarizationServicing {
    static let name = "Energy VAD + CAM++ + cosine clustering"
    static let clusteringThreshold: Float = 0.65

    private struct CandidateTurn {
        let speakerIndex: Int
        let startTime: Double
        let endTime: Double
        let similarity: Float?
    }

    private let embeddingProvider: any SpeakerDiarizationEmbeddingProviding
    private let segmenter: SpeakerDiarizationEnergySegmenter
    private let windowBuilder: SpeakerDiarizationWindowBuilder
    private var modelInfo: SpeakerDiarizationModelInfo?

    init(
        embeddingProvider: any SpeakerDiarizationEmbeddingProviding =
            SpeakerDiarizationCAMPPlusEmbeddingModel(),
        segmenter: SpeakerDiarizationEnergySegmenter = .init(),
        windowBuilder: SpeakerDiarizationWindowBuilder = .init()
    ) {
        self.embeddingProvider = embeddingProvider
        self.segmenter = segmenter
        self.windowBuilder = windowBuilder
    }

    func loadModel(at url: URL) async throws -> SpeakerDiarizationModelInfo {
        let candidate = try await embeddingProvider.loadModel(at: url)
        modelInfo = candidate
        return candidate
    }

    func diarize(mediaAt url: URL) async throws -> SpeakerDiarizationResult {
        let clock = ContinuousClock()
        let decodeStart = clock.now
        let audio = try await SpeakerDiarizationAudioDecoder.decode(url: url)
        return try await diarize(
            audio: audio,
            decodeSeconds: (clock.now - decodeStart).coreAISeconds
        )
    }

    func diarize(audio: SpeakerDiarizationAudio) async throws -> SpeakerDiarizationResult {
        try await diarize(audio: audio, decodeSeconds: 0)
    }

    private func diarize(
        audio: SpeakerDiarizationAudio,
        decodeSeconds: Double
    ) async throws -> SpeakerDiarizationResult {
        guard let modelInfo else {
            throw SpeakerDiarizationError.modelNotLoaded
        }
        guard audio.sampleRate == SpeakerDiarizationCAMPPlusFeatureExtractor.sampleRate else {
            throw SpeakerDiarizationError.unexpectedDecodedFormat(
                sampleRate: Double(audio.sampleRate),
                channelCount: 1
            )
        }

        let clock = ContinuousClock()
        let totalStart = clock.now
        let segmentationStart = clock.now
        let regions = segmenter.regions(in: audio)
        let segmentationSeconds = (clock.now - segmentationStart).coreAISeconds
        let windows = windowBuilder.windows(
            for: regions,
            sampleRate: audio.sampleRate
        )

        var featureExtractionSeconds = Double.zero
        var inferenceSeconds = Double.zero
        var clusterer = SpeakerDiarizationSpeakerClusterer(
            similarityThreshold: Self.clusteringThreshold
        )
        var candidates: [CandidateTurn] = []
        candidates.reserveCapacity(windows.count)
        for window in windows {
            try Task.checkCancellation()
            let modelSamples = try windowBuilder.modelSamples(
                for: window,
                audio: audio,
                sampleCount: SpeakerDiarizationCAMPPlusFeatureExtractor.sampleCount
            )
            let featureStart = clock.now
            let features = try SpeakerDiarizationCAMPPlusFeatureExtractor.extract(
                samples: modelSamples
            )
            featureExtractionSeconds += (clock.now - featureStart).coreAISeconds

            let inferenceStart = clock.now
            let embedding = try await embeddingProvider.embedding(for: features)
            inferenceSeconds += (clock.now - inferenceStart).coreAISeconds
            try Task.checkCancellation()
            let assignment = try clusterer.assign(embedding: embedding)
            candidates.append(
                CandidateTurn(
                    speakerIndex: assignment.speakerIndex,
                    startTime: window.startTime(sampleRate: audio.sampleRate),
                    endTime: window.endTime(sampleRate: audio.sampleRate),
                    similarity: assignment.similarity
                )
            )
        }

        return SpeakerDiarizationResult(
            engineName: Self.name,
            turns: Self.merge(candidates),
            generatedAt: .now,
            evidence: SpeakerDiarizationEvidence(
                modelName: modelInfo.assetName,
                speechRegionCount: regions.count,
                analysisWindowCount: windows.count,
                decodeSeconds: decodeSeconds,
                segmentationSeconds: segmentationSeconds,
                featureExtractionSeconds: featureExtractionSeconds,
                inferenceSeconds: inferenceSeconds,
                totalSeconds: decodeSeconds + (clock.now - totalStart).coreAISeconds,
                clusteringThreshold: Self.clusteringThreshold
            )
        )
    }

    private static func merge(_ candidates: [CandidateTurn]) -> [SpeakerDiarizationTurn] {
        var merged: [CandidateTurn] = []
        for candidate in candidates {
            if let previous = merged.last,
               previous.speakerIndex == candidate.speakerIndex,
               candidate.startTime - previous.endTime <= 0.35 {
                merged[merged.count - 1] = CandidateTurn(
                    speakerIndex: previous.speakerIndex,
                    startTime: previous.startTime,
                    endTime: candidate.endTime,
                    similarity: Self.minimumSimilarity(
                        previous.similarity,
                        candidate.similarity
                    )
                )
            } else {
                merged.append(candidate)
            }
        }
        return merged.enumerated().map { index, candidate in
            SpeakerDiarizationTurn(
                id: index,
                speakerName: "Speaker \(candidate.speakerIndex + 1)",
                startTime: candidate.startTime,
                endTime: candidate.endTime,
                clusterSimilarity: candidate.similarity.map(Double.init)
            )
        }
    }

    private static func minimumSimilarity(_ left: Float?, _ right: Float?) -> Float? {
        switch (left, right) {
        case (.some(let left), .some(let right)):
            min(left, right)
        case (.some(let value), .none), (.none, .some(let value)):
            value
        case (.none, .none):
            nil
        }
    }

}
