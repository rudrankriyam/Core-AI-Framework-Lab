# Core AI Framework Example

Early examples for Apple's new `CoreAI.framework` in Xcode 27 beta.

This repository is intentionally compiler-first. It verifies the public SDK surface, documents the new framework shape, and gives us a small SwiftUI app that can grow into real model examples once compatible Core AI model assets and iOS 27 runtime devices/simulators are available.

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

- `CoreAILab/` - SwiftUI app target that imports `CoreAI`
- `CoreAILabCore/` - small reusable helpers for Core AI API discovery
- `CoreAILabCore/Examples/` - focused examples for cache policy, function descriptors, inference scaffolding, tensors, and images
- `coreai.md` - notes from the local Xcode 27 SDK interfaces
- `project.yml` - XcodeGen project definition

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

Running inference requires a real compatible CoreAI model asset and input values that match the function descriptors. The scaffold is in `CoreAIInferenceExamples.swift`.

## Generate the Xcode Project

```bash
cd Core-AI-Framework-Example
xcodegen generate
```

## Build

Use the expanded Xcode beta directly:

```bash
DEVELOPER_DIR=/Users/rudrank/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild -project CoreAILab.xcodeproj \
  -scheme CoreAILab \
  -destination 'generic/platform=iOS' \
  -derivedDataPath ./build \
  build
```

This currently compiles successfully against `iPhoneOS27.0.sdk`. Xcode may still print beta-environment warnings about CoreDevice/CoreSimulator until the matching iOS/macOS runtime pieces are installed.

## Current Limitations

- No bundled model asset yet. The SDK exposes the runtime APIs, but this repo still needs a real compatible CoreAI model package before it can include a complete inference demo.
- `NDArrayDescriptor` and `ImageDescriptor` are inspectable from the public API, but their direct initializers are not public in this beta seed.
- Simulator availability still needs validation with matching Xcode 27/iOS 27 runtime components.
- The API is beta and may move quickly between Xcode seeds.

## Current SDK Shape

`CoreAI.framework` is a public framework in Xcode 27 beta, but the top-level Swift module mostly re-exports `CoreAIDelegates`. The usable public API fans out into subframeworks:

- `CoreAIAsset`
- `CoreAIDelegates`
- `CoreAIRuntime`
- `CoreAICompiler`
- `CoreAICommon`
- `CoreAICache`

See `coreai.md` for the current symbol notes.
