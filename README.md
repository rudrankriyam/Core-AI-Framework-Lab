# Core AI Framework Lab

[![Xcode 27 beta](https://img.shields.io/badge/Xcode-27%20beta-147EFB?logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2027%20%7C%20macOS%2027-lightgrey)](https://developer.apple.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A hands-on lab for Apple's `CoreAI.framework` in Xcode 27 beta.

The main experiment is a native Chatterbox Turbo text-to-speech workspace. The
app bundles the converted model, tokenizes text in Swift, and runs the complete
T3 -> S3Gen -> HiFT pipeline through Core AI. It does not use MLX, Python, a
server, or a model-download step at runtime.

CoreAI currently looks like a lower-level model runtime and asset framework:

```text
model asset URL
-> AIModelAsset metadata and summary
-> AIModel specialization
-> AIModelCache compiled artifact lookup
-> InferenceFunction descriptor inspection
-> NDArray or image inputs
-> async inference outputs
```

It is not a replacement for `FoundationModels`. Foundation Models is still the high-level language model API. CoreAI is closer to the model asset/runtime/specialization layer.

## Requirements

- Xcode 27 beta
- iOS 27.0+ or macOS 27.0+
- Swift 6.4 toolchain from Xcode 27 beta

## What's Inside

- `CoreAILab/` - SwiftUI app with the Chatterbox synthesis workspace
- `CoreAILabCore/` - small reusable helpers for Core AI API discovery
- `CoreAILabCore/Chatterbox/` - Core AI model storage, specialization, and function-contract code
- `CoreAILabCore/Examples/` - focused examples for cache policy, function descriptors, inference scaffolding, tensors, and images
- `Conversion/Chatterbox/` - weighted PyTorch-to-Core-AI exporters, parity tests, and a contract probe
- `coreai.md` - notes from the local Xcode 27 SDK interfaces
- `project.yml` - XcodeGen project definition

## Chatterbox Workspace

The macOS target embeds four `.aimodel` assets and a Hugging Face tokenizer:

| Asset | Precision | Entrypoints | Role |
| --- | --- | --- | --- |
| T3 embeddings | FP16 | `prefill`, `decode` | Built-in voice conditioning plus text/speech embeddings |
| T3 transformer | mixed INT4/INT8/FP16 | `prefill`, `decode` | Autoregressive speech-token generation with persistent KV caches |
| S3Gen | FP16 | `main` | 256 speech tokens to 512 generated mel frames |
| HiFT vocoder | FP16 | `vocoder` | 80-bin mel frames to 24 kHz waveform audio |

The bundle occupies about 600 MiB on disk and reports 625.1 MB of allocated
model data on the tested Mac. The app validates all six native entrypoints
before enabling generation and persistently caches Core AI specialization.

The production export has capacity for 253 generated speech tokens plus three
end-silence tokens. That is a 10.24-second graph window. The WAV writer trims
the static graph output to the model's actual stop token, so short utterances do
not contain several seconds of padding.

Verified on an M5 Mac (`h17g`) with Xcode 27 beta:

- 139 generated tokens
- 5.68 seconds of 24 kHz mono PCM audio
- 4.85 seconds for a warm Release button-driven app run
- 0.85 real-time factor, or 1.17x faster than real time
- complete Whisper transcript ending in `with Core AI.`
- zero clipped samples

See `Conversion/Chatterbox/README.md` for reproducible conversion, parity, and
runtime-validation commands.

## Example Coverage

| Area | File | What it shows |
| --- | --- | --- |
| Runtime discovery | `CoreAIDiscoverySnapshot.swift` | Architecture name, available compute units, default specialization options. |
| Model assets | `CoreAIModelAssetInspector.swift` | `AIModelAsset.isValid`, metadata, function names, compute types. |
| Model loading | `CoreAIModelLoader.swift` | `AIModel.specialize`, preferred compute unit options, function loading. |
| Cache policy | `Examples/CoreAIModelCacheExamples.swift` | Default/app-group caches, persistent policy, purge conditions, cache cleanup. |
| Function descriptors | `Examples/CoreAIFunctionDescriptorExamples.swift` | Input/state/output names and descriptor summaries. |
| Inference | `Examples/CoreAIInferenceExamples.swift` | The model/function/input flow for `function.run(inputs:)`. |
| Values | `Examples/CoreAIValueDescriptorExamples.swift` | Public descriptor inspection for tensors and images. |

The app lists these examples on launch so the repo is easy to navigate from Xcode.

## How To Use CoreAI

The current public flow is:

```swift
import CoreAI

let modelURL = URL(fileURLWithPath: "/path/to/model")

guard AIModelAsset.isValid(at: modelURL) else {
    throw CocoaError(.fileReadUnknown)
}

let asset = try AIModelAsset(contentsOf: modelURL)
let summary = try asset.summary(includingStatistics: true)

let model = try await AIModel.specialize(
    contentsOf: modelURL,
    options: SpecializationOptions(preferredComputeUnitKind: .neuralEngine),
    cache: .default,
    cachePolicy: .default
)

guard let functionName = model.functionNames.first,
      let function = try model.loadFunction(named: functionName) else {
    return
}

let descriptor = function.descriptor
print(descriptor.inputNames)
print(descriptor.outputNames)
```

The complete native runtime is implemented in
`CoreAILabCore/Chatterbox/ChatterboxCoreAIEngine.swift`.

## Generate the Xcode Project

```bash
cd Core-AI-Framework-Lab
xcodegen generate
```

## Build and Run on macOS

Use Xcode 27 beta directly. A machine-wide `xcode-select` pointing at an older
Xcode will not expose the `CoreAI` module.

```bash
DEVELOPER_DIR=/path/to/Xcode-beta.app/Contents/Developer \
xcodebuild -project CoreAIFrameworkLab.xcodeproj \
  -scheme CoreAILabMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ./build/Xcode27 \
  build

open build/Xcode27/Build/Products/Debug/CoreAILab.app
```

Run the macOS contract tests with the same scheme:

```bash
DEVELOPER_DIR=/path/to/Xcode-beta.app/Contents/Developer \
xcodebuild -project CoreAIFrameworkLab.xcodeproj \
  -scheme CoreAILabMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ./build/Xcode27 \
  test
```

The app and tests compile successfully against `MacOSX27.0.sdk`. The iOS app remains available through the `CoreAILab` scheme for device builds.

## Current Limitations

- The app ships one fixed Chatterbox Turbo voice prepared from Resemble AI's
  official `ivr_female_01` demo reference. The raw reference recording is not
  bundled, and runtime voice selection or reference-voice cloning is not
  exposed.
- One native graph invocation supports up to 253 generated speech tokens, or
  about 10.12 seconds of speech plus the 120 ms end-silence tail. The app
  rejects an utterance that reaches this ceiling instead of returning clipped
  audio.
- The 600 MiB model bundle is included only in the macOS target.
- Simulator and device support may differ during the Xcode 27 beta cycle.
- Core AI and its converter packages are beta APIs and may move between seeds.

## Current SDK Shape

`CoreAI.framework` is a public framework in Xcode 27 beta, but the top-level Swift module mostly re-exports `CoreAIDelegates`. The usable public API fans out into subframeworks:

- `CoreAIAsset`
- `CoreAIDelegates`
- `CoreAIRuntime`
- `CoreAICompiler`
- `CoreAICommon`
- `CoreAICache`

See `coreai.md` for the current symbol notes.

## Contributing

Contributions, experiments, and corrections are welcome. Please open an issue
or submit a pull request.

## License

Core AI Framework Lab is available under the MIT License. See
[`LICENSE`](LICENSE) for details.
