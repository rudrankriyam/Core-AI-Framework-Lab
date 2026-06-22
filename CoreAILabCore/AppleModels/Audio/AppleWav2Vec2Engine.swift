import CoreAI
import Foundation

actor AppleWav2Vec2Engine: AppleAudioTranscribing {
    private enum InputPrecision {
        case float16
        case float32

        var name: String {
            switch self {
            case .float16: "float16"
            case .float32: "float32"
            }
        }
    }

    private struct LoadedModel {
        let model: AIModel
        let function: InferenceFunction
        let sampleCount: Int
        let inputPrecision: InputPrecision
    }

    private var loadedModel: LoadedModel?

    func loadModel(at url: URL) async throws -> AppleAudioModelInfo {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let model = try await AIModel.specialize(
            contentsOf: url,
            options: .default,
            cache: .default,
            cachePolicy: .default
        )
        guard let function = try model.loadFunction(named: "main") else {
            throw AppleAudioError.missingFunction("main")
        }
        let descriptor = function.descriptor
        guard descriptor.stateNames.isEmpty else {
            throw AppleAudioError.invalidInputContract("the main function must be stateless")
        }
        guard case .ndArray(let inputDescriptor)? = descriptor.inputDescriptor(of: "waveform") else {
            throw AppleAudioError.invalidInputContract("missing NDArray input named waveform")
        }
        guard inputDescriptor.shape.count == 2,
              inputDescriptor.shape[0] == 1,
              inputDescriptor.shape[1] > 0,
              !inputDescriptor.hasDynamicShape else {
            throw AppleAudioError.invalidInputContract(
                "use Apple's default static [1, 80000] export"
            )
        }
        guard inputDescriptor.scalarType == .float16 || inputDescriptor.scalarType == .float32 else {
            throw AppleAudioError.unsupportedScalarType(
                String(describing: inputDescriptor.scalarType)
            )
        }
        guard case .ndArray(let outputDescriptor)? = descriptor.outputDescriptor(of: "emission"),
              outputDescriptor.shape.count == 3,
              outputDescriptor.shape[0] == 1,
              outputDescriptor.shape[2] == Wav2Vec2CTCDecoder.labels.count else {
            throw AppleAudioError.invalidOutputContract(
                "expected an emission tensor shaped [1, time, \(Wav2Vec2CTCDecoder.labels.count)]"
            )
        }

        let inputPrecision: InputPrecision = inputDescriptor.scalarType == .float16
            ? .float16
            : .float32
        let candidate = LoadedModel(
            model: model,
            function: function,
            sampleCount: inputDescriptor.shape[1],
            inputPrecision: inputPrecision
        )
        loadedModel = candidate
        return AppleAudioModelInfo(
            sampleCount: candidate.sampleCount,
            sampleRate: AppleAudioSampleLoader.sampleRate,
            scalarTypeName: candidate.inputPrecision.name
        )
    }

    func transcribe(audioAt url: URL) async throws -> AppleAudioTranscriptionResult {
        guard let loadedModel else {
            throw AppleAudioError.modelNotLoaded
        }
        let maximumDuration = Double(loadedModel.sampleCount) / AppleAudioSampleLoader.sampleRate
        let audio = try AppleAudioSampleLoader.loadMono16k(
            from: url,
            maximumDurationSeconds: maximumDuration
        )
        let waveform = try makeWaveform(
            samples: audio.values,
            sampleCount: loadedModel.sampleCount,
            precision: loadedModel.inputPrecision
        )

        let clock = ContinuousClock()
        let start = clock.now
        var outputs = try await loadedModel.function.run(inputs: ["waveform": waveform])
        let duration = clock.now - start
        guard let emission = outputs.remove("emission")?.ndArray else {
            throw AppleAudioError.missingOutput("emission")
        }
        let transcript = try Wav2Vec2CTCDecoder.decode(
            emissions: CoreAIFloatingPointArray.read(emission),
            shape: emission.shape
        )

        return AppleAudioTranscriptionResult(
            transcript: transcript,
            audioDurationSeconds: audio.durationSeconds,
            inferenceDurationSeconds: duration.coreAISeconds
        )
    }

    private func makeWaveform(
        samples: [Float],
        sampleCount: Int,
        precision: InputPrecision
    ) throws -> NDArray {
        guard samples.count <= sampleCount else {
            throw AppleAudioError.audioTooLong(
                maximumSeconds: Double(sampleCount) / AppleAudioSampleLoader.sampleRate
            )
        }

        var array: NDArray
        switch precision {
        case .float16:
            array = NDArray(shape: [1, sampleCount], scalarType: .float16)
            fill(&array, samples: samples, as: Float16.self)
        case .float32:
            array = NDArray(shape: [1, sampleCount], scalarType: .float32)
            fill(&array, samples: samples, as: Float.self)
        }
        return array
    }

    private func fill<Element>(
        _ array: inout NDArray,
        samples: [Float],
        as type: Element.Type
    ) where Element: BinaryFloatingPoint & BitwiseCopyable {
        var view = array.mutableView(as: type)
        view.withUnsafeMutablePointer { pointer, shape, _ in
            let count = shape[0] * shape[1]
            for index in 0..<count {
                pointer[index] = index < samples.count ? Element(samples[index]) : 0
            }
        }
    }

}
