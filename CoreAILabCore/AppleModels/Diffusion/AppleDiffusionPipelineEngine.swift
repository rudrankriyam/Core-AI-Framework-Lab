import CoreAIDiffusionPipeline
import Foundation

actor AppleDiffusionPipelineEngine: AppleDiffusionGenerating {
    private enum LoadedPipeline {
        case stable(StableDiffusionPipeline)
        case stableDiffusion3(SD3Pipeline)
        case flux2(Flux2Pipeline)

        var descriptor: PipelineDescriptor {
            switch self {
            case .stable(let pipeline):
                pipeline.descriptor
            case .stableDiffusion3(let pipeline):
                pipeline.descriptor
            case .flux2(let pipeline):
                pipeline.descriptor
            }
        }

        var defaultImageSize: (width: Int, height: Int) {
            switch self {
            case .stable(let pipeline):
                pipeline.defaultImageSize
            case .stableDiffusion3(let pipeline):
                pipeline.defaultImageSize
            case .flux2(let pipeline):
                pipeline.defaultImageSize
            }
        }

        var supportsImageToImage: Bool {
            switch self {
            case .stable(let pipeline):
                pipeline.supportsImageToImage
            case .stableDiffusion3(let pipeline):
                pipeline.supportsImageToImage
            case .flux2(let pipeline):
                pipeline.supportsImageToImage
            }
        }

        var schedulerType: SchedulerType {
            switch self {
            case .stable:
                .dpmSolverMultistep
            case .stableDiffusion3, .flux2:
                .discreteFlow
            }
        }

        var displayName: String {
            switch self {
            case .stable:
                "Stable Diffusion"
            case .stableDiffusion3:
                "Stable Diffusion 3"
            case .flux2:
                "FLUX.2"
            }
        }

        func generate(
            configuration: PipelineConfiguration,
            progressHandler: (PipelineProgress) -> Bool
        ) async throws -> GenerationResult {
            switch self {
            case .stable(let pipeline):
                try await pipeline.generateImages(
                    configuration: configuration,
                    progressHandler: progressHandler
                )
            case .stableDiffusion3(let pipeline):
                try await pipeline.generateImages(
                    configuration: configuration,
                    progressHandler: progressHandler
                )
            case .flux2(let pipeline):
                try await pipeline.generateImages(
                    configuration: configuration,
                    progressHandler: progressHandler
                )
            }
        }
    }

    private var pipeline: LoadedPipeline?
    private var scopedResourceURL: URL?
    private var isAccessingScopedResource = false

    deinit {
        if isAccessingScopedResource {
            scopedResourceURL?.stopAccessingSecurityScopedResource()
        }
    }

    func loadPipeline(at url: URL) async throws -> AppleDiffusionModelInfo {
        let isAccessing = url.startAccessingSecurityScopedResource()

        do {
            let descriptor = try PipelineDescriptor.resolve(at: url, config: .auto)
            let loadedPipeline: LoadedPipeline
            switch descriptor.type {
            case .stableDiffusion3:
                loadedPipeline = .stableDiffusion3(
                    try await SD3Pipeline(from: url, config: .explicit(descriptor))
                )
            case .flux2:
                loadedPipeline = .flux2(
                    try await Flux2Pipeline(
                        from: url,
                        config: .explicit(descriptor),
                        mode: .auto
                    )
                )
            case .stableDiffusion, .stableDiffusionXL, nil:
                loadedPipeline = .stable(
                    try await StableDiffusionPipeline.load(
                        from: url,
                        config: .explicit(descriptor)
                    )
                )
            }

            releaseScopedResource()
            pipeline = loadedPipeline
            scopedResourceURL = url
            isAccessingScopedResource = isAccessing

            let size = loadedPipeline.defaultImageSize
            return AppleDiffusionModelInfo(
                pipelineName: loadedPipeline.displayName,
                width: size.width,
                height: size.height,
                supportsImageToImage: loadedPipeline.supportsImageToImage
            )
        } catch {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            throw error
        }
    }

    func generate(_ request: AppleDiffusionRequest) async throws -> AppleDiffusionResult {
        guard let pipeline else {
            throw AppleDiffusionError.pipelineNotLoaded
        }

        let descriptor = pipeline.descriptor
        let size = pipeline.defaultImageSize
        let configuration = PipelineConfiguration(
            prompt: request.prompt,
            negativePrompt: request.negativePrompt,
            seed: request.seed,
            stepCount: request.stepCount,
            guidanceScale: request.guidanceScale,
            schedulerType: pipeline.schedulerType,
            encoderScaleFactor: descriptor.encoderScaleFactor ?? 0.18215,
            decoderScaleFactor: descriptor.decoderScaleFactor ?? 0.18215,
            decoderShiftFactor: descriptor.decoderShiftFactor ?? 0,
            decodeResolution: .auto,
            originalSize: Float(size.width),
            targetSize: Float(size.width),
            lazyModelLoading: true
        )

        let clock = ContinuousClock()
        let start = clock.now
        let generated = try await pipeline.generate(configuration: configuration) { _ in
            !Task.isCancelled
        }
        try Task.checkCancellation()
        guard let image = generated.images.first else {
            throw AppleDiffusionError.noImageGenerated
        }

        return AppleDiffusionResult(
            image: image,
            durationSeconds: Self.seconds(from: clock.now - start)
        )
    }

    private func releaseScopedResource() {
        if isAccessingScopedResource {
            scopedResourceURL?.stopAccessingSecurityScopedResource()
        }
        scopedResourceURL = nil
        isAccessingScopedResource = false
    }

    private static func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
