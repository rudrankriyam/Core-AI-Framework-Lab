# Core AI Framework Lab

[![Xcode 27 beta](https://img.shields.io/badge/Xcode-27%20beta-147EFB?logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2027%20%7C%20macOS%2027-lightgrey)](https://developer.apple.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A native workbench for Apple's `CoreAI.framework` in Xcode 27 beta.

Core AI Lab connects a searchable snapshot of Apple's open-source model
recipes, visual conversion, generic `.aimodel` inspection, a descriptor-driven
function workbench, and task-specific model playgrounds. Chatterbox Turbo
remains the custom end-to-end stress test. YOLOS Tiny is the first official
Apple-repository example, exported locally and run through Apple's own
`CoreAIObjectDetection` Swift package.

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
- `CoreAILabCore/AppleModels/` - pinned Apple registry models, recipe metadata, and the YOLOS runtime adapter
- `CoreAILab/Features/AppleModels/` - searchable model library and object-detection playground
- `CoreAILab/Features/Conversion/` - visual recipe configuration, environment checks, live logs, cancellation, and artifact handoff
- `CoreAILabCore/Conversion/` - typed command planning and macOS subprocess execution without a shell
- `CoreAILab/Features/AssetInspector/` - generic `.aimodel` metadata and function inspector
- `CoreAILab/Features/FunctionWorkbench/` - specialization, generated inputs, inference, and output summaries
- `CoreAILabCore/FunctionWorkbench/` - descriptor contracts, safe tensor allocation, and generic runtime execution
- `CoreAILab/Resources/AppleModels/` - generated snapshot of Apple's public model registry
- `Conversion/Chatterbox/` - weighted PyTorch-to-Core-AI exporters, parity tests, and a contract probe
- `APPLE_CORE_AI_CAPABILITIES.md` - current official capability and tooling audit
- `GRAND_PLAN.md` - product, architecture, and milestone plan reconstructed from the local Core AI work
- `coreai.md` - notes from the local Xcode 27 SDK interfaces
- `project.yml` - XcodeGen project definition

## Apple Model Library

The app includes all 33 presets from Apple [`coreai-models`](https://github.com/apple/coreai-models)
revision `e358c8435679c904687f8070eb95150e36e4b76d`. These are conversion recipes,
not downloadable `.aimodel` binaries. Each entry shows its source model,
platform, compression/context defaults, exact export command, pinned recipe,
and the matching Apple Swift runtime when one exists.

Refresh the checked-in snapshot from a local Apple repository clone:

```bash
python3 Scripts/update_apple_model_catalog.py /path/to/coreai-models
xcodegen generate
```

Model weights are not bundled or redistributed by the app. When you start a
conversion, the selected upstream recipe may fetch its original model weights;
their licenses, authentication requirements, and source revisions remain
independent of Apple's BSD-3-Clause recipe repository.

## Visual Conversion Workbench

On macOS, open **Convert** or choose **Convert This Recipe** from any Apple
model detail. The workbench lets you:

- choose a pinned Apple recipe, local `apple/coreai-models` clone, output folder, and `uv` executable;
- verify Apple silicon, the selected Core AI Xcode toolchain, pinned revision, clean recipe worktree, write access, and available storage;
- review the exact export arguments and utility-model precision before starting;
- stream the original Python/PyTorch output, cancel the child process, and preserve a timestamped evidence log;
- inspect generated `.aimodel` and `.aimodelc` packages directly in Core AI Lab.

The app passes a typed executable URL and argument array to Foundation
`Process`; the displayed command is never evaluated by a shell. The first run
can create a `uv` environment and download large upstream checkpoints. Gated
models still require the user's own source authentication and license access.

This first conversion slice deliberately uses a local Apple repository clone.
Automatic cloning, resumable jobs across app launches, custom PyTorch recipe
authoring, and content-addressed artifact storage remain later milestones.

## Specialization and Cache Controls

Open any `.aimodel` in **Asset Inspector** to choose automatic, CPU-only, GPU-
preferred, or Neural-Engine-preferred specialization. Core AI Lab checks the
default `AIModelCache` for that exact asset and profile, specializes with the
standard reclaimable policy, and can remove one profile or every cached
profile for the selected source asset.

These controls use only Apple's public cache APIs. Core AI does not expose a
cache directory, entry sizes, ages, or an enumerable inventory, so the Lab
reports honest known-entry hit/miss state instead of guessing from private
filesystem paths. Removing an entry means the model must specialize again.
Persistent cache policy is intentionally not offered for session-scoped
imports: Core AI requires the app to retain its opaque model bookmark to load
or remove such an entry after the source disappears. That option belongs with
the planned persistent project library rather than a disposable file picker.

## Generic Function Workbench

Open **Workbench**, choose any `.aimodel`, and specialize it with one of the
same cache and compute profiles. The Lab then lists every function contract and
can run supported stateless functions without a model-specific SwiftUI screen.

The first generic runtime slice supports fixed or dynamic NDArray inputs using
zeros or repeatable seeded random values across Bool, signed and unsigned
integers, Float16, Float32, and Float64. Input allocation is capped at 256 MiB
per tensor. Results include shape, strides, element count, a value preview, and
sampled minimum, maximum, mean, and non-finite counts. Large outputs sample at
most 65,536 elements so inspection does not copy the entire tensor.

All input, state, and output descriptors remain visible when a function cannot
run generically. Stateful functions, image inputs, unknown descriptors, and
packed or specialized scalar formats are disabled with an explicit reason;
they still belong in task adapters such as Apple's YOLOS runtime. A fresh Core
AI function instance is loaded for every run while the specialized model stays
cached.

## Run Apple's YOLOS Tiny Example

From a clone of Apple's repository at the pinned revision:

```bash
uv run models/yolo/export.py \
  --model hustvl/yolos-tiny \
  --dtype float16
```

Open **Apple Models -> yolos-tiny -> Object Detection Playground**, import the
generated `yolos-tiny_float16_static.aimodel`, choose an image, and run
detection. The app uses Apple's `ObjectDetector` for image preprocessing,
Core AI inference, COCO post-processing, labels, and confidence scores.

The verified export is a 63.4 MB FP16 asset with a static Float16
`[1, 3, 512, 512]` input, `logits [1, 100, 92]`, and
`pred_boxes [1, 100, 4]`. On the tested Mac, warm inference took 23.7-49 ms.
The generated asset reports the upstream YOLOS Apache-2.0 license.

## Asset Inspector

Open any `.aimodel` package to inspect validity, author, license, description,
function names, and compute types without adding the asset to the app bundle.
This works with standalone Apple recipe outputs and individual assets inside
language, diffusion, or segmentation resource folders.

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

- Apple's repository ships export code and runtime utilities, not converted
  model weights. Export remains a local `uv` workflow in this first slice.
- YOLOS object detection is the first Apple-runtime playground. Apple's
  language, diffusion, and segmentation products are catalogued but their
  task-specific Lab surfaces are future milestones.
- Imported assets are session-scoped. A content-addressed persistent artifact
  library is planned but not included yet.
- The generic function workbench currently generates NDArray inputs only.
  Stateful execution, image-input adaptation, imported fixtures, repeated
  benchmarks, and raw-output export remain later Runtime Studio work.
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
