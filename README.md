# Core AI Framework Lab

[![Xcode 27 beta](https://img.shields.io/badge/Xcode-27%20beta-147EFB?logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2027%20%7C%20macOS%2027-lightgrey)](https://developer.apple.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A native workbench for Apple's `CoreAI.framework` in Xcode 27 beta.

Core AI Lab connects persistent projects, content-addressed model storage, a
searchable snapshot of Apple's open-source model recipes, visual conversion,
generic `.aimodel` inspection, a descriptor-driven function workbench, and
task-specific model playgrounds. Chatterbox Turbo remains the custom end-to-end
stress test. YOLOS Tiny is the first official Apple-repository example,
exported locally and run through Apple's own `CoreAIObjectDetection` Swift
package.

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
- `CoreAILabCore/AppleModels/` - pinned Apple registry models plus language, vision, and segmentation runtime adapters
- `CoreAILab/Features/AppleModels/` - searchable model library and task-specific playgrounds
- `CoreAILab/Features/Conversion/` - visual recipe configuration, environment checks, live logs, cancellation, and artifact handoff
- `CoreAILabCore/Conversion/` - typed command planning and macOS subprocess execution without a shell
- `CoreAILab/Features/Projects/` - persistent project library, artifact inventory, and Inspector/Workbench handoff
- `CoreAILabCore/Projects/` - SwiftData project schema and atomic SHA-256 artifact storage
- `CoreAILabCore/Manifests/` - versioned, Codable recipe, target, artifact, pipeline, and capacity contracts with reference and path validation
- `CoreAILab/Features/AssetInspector/` - generic `.aimodel` metadata and function inspector
- `CoreAILab/Features/FunctionWorkbench/` - specialization, generated inputs, inference, and output summaries
- `CoreAILabCore/FunctionWorkbench/` - descriptor contracts, safe tensor allocation, and generic runtime execution
- `CoreAILab/Features/RuntimeStudio/` - searchable recipe-backed experience routing, run status, and comparison selection
- `CoreAILabCore/RuntimeStudio/` - versioned experience registry, shared lifecycle coordinator, and optional project timing evidence
- `CoreAILab/Resources/AppleModels/` - generated snapshot of Apple's public model registry
- `CoreAILab/Resources/RuntimeStudio/` - validated recipe-to-experience mappings for the built-in adapters
- `Conversion/Chatterbox/` - weighted PyTorch-to-Core-AI exporters, parity tests, and a contract probe
- `Conversion/Diarization/` - CAM++ conversion, license audit, semantic validation, and diarization test plan
- `APPLE_CORE_AI_CAPABILITIES.md` - current official capability and tooling audit
- `GRAND_PLAN.md` - product, architecture, and milestone plan reconstructed from the local Core AI work
- `coreai.md` - notes from the local Xcode 27 SDK interfaces
- `CoreAIFrameworkLab.xcodeproj` - checked-in Xcode project for both app targets

## Apple Model Library

The app includes all 33 presets from Apple [`coreai-models`](https://github.com/apple/coreai-models)
revision `e358c8435679c904687f8070eb95150e36e4b76d`. These are conversion recipes,
not downloadable `.aimodel` binaries. Each entry shows its source model,
platform, compression/context defaults, exact export command, pinned recipe,
and the matching Apple Swift runtime when one exists.

Refresh the checked-in snapshot from a local Apple repository clone:

```bash
python3 Scripts/update_apple_model_catalog.py /path/to/coreai-models
```

Model weights are not bundled or redistributed by the app. When you start a
conversion, the selected upstream recipe may fetch its original model weights;
their licenses, authentication requirements, and source revisions remain
independent of Apple's BSD-3-Clause recipe repository.

## Persistent Projects and Artifact Storage

Open **Projects** to create a durable Lab Project, then import a `.aimodel`, an
Apple resource folder, or a supporting file. Project metadata is persisted with
SwiftData at `Application Support/Core AI Lab/Projects.store`. Large artifact
content lives beside it under `Artifacts/` in a streamed SHA-256 store rather
than in the database or repository.

Imports reject symbolic links, hash deterministic relative paths and file
boundaries, copy into a staging directory, verify the staged content, and only
then atomically promote it into the store. Identical content is shared across
projects. Removing the last project reference reclaims the stored copy; deleting
one of several references does not. Stored `.aimodel` packages open directly in
Asset Inspector or Function Workbench. Conversion outputs expose a **Store in
Project** action instead of remaining tied to their original output folder.

Directory imports also retain a versioned manifest of safe relative paths,
streamed per-file SHA-256 digests, and byte counts. Model inspection snapshots
function descriptors, storage and compute types, and operation distribution into
the project library. Source provenance remains editable per project artifact,
while successful
specializations register project-owned cache configurations that can be browsed
and removed without deleting cache entries still referenced by another project.

The project schema also stores immutable recipe-manifest revisions, target
profiles, typed run status, and evidence metadata. These records retain the exact
validated JSON contracts used by a run and survive reopening the SwiftData store.
Controller APIs keep recipe, target, run, and evidence ownership within one Lab
Project. Runtime Studio can optionally record inference status and a successful
run's measured duration as metric evidence. It does not invent output-artifact
records: output persistence still needs a real stored file, digest, and media
contract. Selecting a project for recording reconciles runs interrupted by a
previous app session as failed. Conversion jobs and generic benchmarks are not
yet connected to this coordinator.

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

This conversion slice deliberately uses a local Apple repository clone.
Automatic cloning and custom PyTorch recipe authoring remain later milestones.
The reusable conversion core now includes a versioned durable job store with
legal state transitions, append-only JSONL events, launch-time interruption
reconciliation, and checkpoint reuse decisions tied to a versioned request and
environment identity: full recipe revision, source/lock/executable hashes,
Xcode/SDK builds, relevant child environment, and store-verified no-follow
artifact tree evidence. Job creation is staged atomically, independent store
instances coordinate through a file lock, and a torn final log frame preserves
the valid event prefix for recovery. The visual workbench has not
adopted that store yet: after an app restart it still launches a fresh converter
process rather than claiming that a killed process resumed. Completed output
artifacts can be copied into persistent projects.

## Specialization and Cache Controls

Open any `.aimodel` in **Asset Inspector** to choose automatic, CPU-only, GPU-
preferred, or Neural-Engine-preferred specialization. Core AI Lab checks the
default `AIModelCache` for that exact asset, profile, and frequent-reshape
setting, specializes with the standard reclaimable policy, and can remove one
configuration or every cached profile for the selected source asset. Compute
selection is a preference, not proof that inference ran on one unit.

These controls use only Apple's public cache APIs. Core AI does not expose a
cache directory, entry sizes, ages, or an enumerable inventory, so the Lab
reports honest known-entry hit/miss state instead of guessing from private
filesystem paths. Removing an entry means the model must specialize again.
Persistent cache policy is not offered yet: Core AI requires the app to retain
its opaque model bookmark to load or remove such an entry after the source
disappears. Projects now keep the source artifact stable, but the bookmark still
needs to become versioned project metadata before that policy can be honest.

## Runtime Studio

Open **Runtime Studio** for the registry-backed language, vision, audio,
diffusion, and generic-function experiences. The bundled schema-versioned JSON
declares an exact intended recipe revision and model identifier for a semantic
adapter, capabilities, platforms, and presentation. Runtime Studio excludes
entries that do not declare support for the current OS. EfficientSAM and SAM 3,
as well as all four diffusion presets, prove that a second model can reuse an
existing destination without adding navigation SwiftUI.

Qwen, YOLOS, both segmentation adapters, Wav2Vec2, diffusion runs, and direct
Function Workbench invocations report one shared lifecycle: running, succeeded,
failed, or canceled. Attempts remain cold until one run succeeds for the same
experience and imported model identity in a Runtime Studio session; later
attempts are warm. A selected comparison identity is captured with each run,
but this slice does not claim numerical or semantic A/B comparison of outputs.

Choose a Lab Project under **Run Recording** to persist future runtime status.
The importer checks that an artifact's identifiable model family matches the
selected registry entry. Current Apple exports do not carry artifact-bound
recipe/revision proof, so successful runs add timing-only metric evidence with
explicit `unverified_intent` provenance and never link the selected project
recipe revision. Every persisted run also carries validation evidence that
states whether its recipe provenance is unattributed or unverified intent.
Terminal run status and its metric are saved together; a
failed or ambiguously reported save remains available through **Retry Run
Recording**, and retries do not duplicate the metric. Evidence also records the
experience, actual model identity, cold/warm class, duration, and optional
comparison identity. Selecting a project also marks any running records left by
an interrupted previous app session as failed.
Imported model bookmarks, produced output files, cross-launch warm-state
recovery, embeddings, and output-quality comparison remain follow-up work.
No experience downloads model weights; each adapter still requires a locally
exported bundle under its upstream license.

## Generic Function Workbench

Open **Runtime Studio -> Function Workbench**, choose any `.aimodel`, and
specialize it with one of the same cache and compute profiles. The Lab then
lists every function contract and can run supported stateless functions without
a model-specific SwiftUI screen. Direct invocations use Runtime Studio's shared
lifecycle and optional project recording; the separate multi-trial benchmark
reports remain session-only evidence.

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

### Repeatable Benchmarks

The Workbench can run a bounded benchmark using the same generated input plans.
The default protocol performs one excluded warmup followed by five sequential
measured runs on one loaded function and one deterministic input set. Every
trial remains visible alongside function-load, input-setup, and warmup timing;
the summary reports minimum, median, mean, maximum, standard deviation, and
runs per second. P95 appears only for 20 or more measured runs.

Each in-memory report captures the asset, function, shapes, generators, seeds,
full specialization configuration, cache state, Core AI device architecture,
OS, available compute units, build configuration, and start/end thermal state.
Use a Release build for comparisons. **Stop After Current Inference** cancels
between Core AI calls because an active generic inference cannot be interrupted
by the Lab, while retaining every measured trial that completed. The history
supports honest A/B checks across shapes and compute or
reshape preferences without claiming hardware placement, energy, or memory
measurements that Core AI did not report.

### Integration Export

After specialization, **Export Integration** packages the inspected standalone
asset with a schema-versioned contract manifest, deterministic SHA-256 tree
digest, README, and generated Swift runtime. Generated methods cover every
stateless NDArray-input function and preserve exact Core AI function names.
Stateful, image-input, and unknown contracts remain in the manifest with an
explicit reason instead of receiving unsafe placeholder code. Large assets are
streamed into a same-folder temporary package that appears atomically only
after the complete export succeeds. Each package also includes a deterministic,
non-executed `compile-model.sh` for optional iOS and macOS 27 ahead-of-time
compilation with the selected GPU or Neural Engine preference and reshape hint.
CPU-only remains a runtime `SpecializationOptions.cpuOnly` choice because
`coreai-build compile` does not expose a CPU-only flag.

### Typed Pipeline Contract

`CoreAILabCore/Pipelines` defines the versioned, deterministic contract that
Recipe Studio, Pipeline Studio, and future generated runtimes share. A pipeline
is an asset-level directed graph with typed ports, explicit state ownership,
seeded randomness, bounded loops, and a versioned host-operator registry.

Validation rejects missing endpoints, incompatible value contracts, duplicate
input wiring, cycles, ambiguous state ownership, randomness without exactly one
seed source, and loops without both a finite iteration bound and stop input.
Pipeline Studio now edits that asset-level contract directly: nodes, typed
ports, and compatible single-source edges remain under the same validator used
by the deterministic JSON codec. This editor does not execute the graph; the
generic pipeline runtime remains a separate milestone.

### Custom Recipe Studio Foundation

Recipe Studio provides a versioned, deterministic authoring manifest and native
editors for a PyTorch source and module, concrete example inputs, bounded dynamic
dimensions, explicit state bindings, externalization rules, and function
entrypoints. Its validation keeps cross-references and the embedded pipeline
contract honest before a recipe can be encoded.

Unsupported-operation findings retain the operator, module path, source file,
line, example shapes, and an optional built-in rewrite suggestion. The checked-in
rewrite catalog records patterns already evidenced by the Chatterbox adapters.
Generated Python custom-lowering and Metal-kernel files are deliberately failing
stubs (`NotImplementedError` and `#error`) until an author implements and
parity-tests them.

This checkpoint is an in-memory authoring foundation. It does not yet run the
diagnostic worker, persist recipe workspaces into Lab Projects, execute pipelines,
or migrate Chatterbox conversion and runtime orchestration into the recipe system.

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

## Run Apple's Qwen3 0.6B Example

Export Qwen from the root of the pinned Apple repository clone. The macOS
preset uses a 4-bit model and an 8,192-token context:

```bash
uv run coreai.llm.export Qwen/Qwen3-0.6B \
  --compression 4bit \
  --compute-precision float16 \
  --max-context-length 8192
```

Open **Apple Models -> qwen3-0.6b -> Qwen3 0.6B Playground** and import the
entire exported resource folder, not one nested `.aimodel`. The playground
loads Apple's `CoreAILanguageModel`, creates a `FoundationModels`
`LanguageModelSession`, and supports bounded generation, cancellation, and a
fresh-session reset. The iOS export command is shown beside the macOS command
in the app.

Converted weights and tokenizer resources remain local and subject to Qwen's
upstream license. Set `COREAI_QWEN_BUNDLE_PATH` to an exported resource folder
to opt into the real-model integration test.

## Run Apple's Diffusion Examples

Apple's registry includes Stable Diffusion 1.5, Stable Diffusion 2.1, Stable
Diffusion 3.5 Medium, and FLUX.2 Klein 4B presets. Export any of them from the
pinned repository clone; for example:

```bash
uv run coreai.diffusion.export runwayml/stable-diffusion-v1-5 \
  --compression none \
  --compute-precision float16
```

Open its entry under **Apple Models**, choose the diffusion playground, and
import the entire exported resource folder. The Lab resolves Apple's v0.2
metadata and dispatches to `StableDiffusionPipeline`, `SD3Pipeline`, or
`Flux2Pipeline`. Prompt, negative prompt, seed, step count, and guidance are
editable, generation is cancellable, and the resulting image and elapsed time
stay on device.

The Lab keeps security-scoped access alive for the loaded folder because
Apple's pipelines load some components lazily during generation. Set
`COREAI_DIFFUSION_BUNDLE_PATH` to opt into a one-step real-model integration
test.

Stable Diffusion 3.5 Medium is gated on Hugging Face. Accept Stability AI's
upstream terms and authenticate with `hf auth login` before export; Core AI Lab
never reads or stores those credentials. FLUX.2 does not consume a negative
prompt, so the playground hides that control after loading a FLUX.2 bundle.

## Run Apple's Wav2Vec2 Audio Example

Export Apple's static five-second Wav2Vec2 recipe from the pinned repository:

```bash
uv run models/wav2vec2/export.py \
  --model wav2vec2_asr_base_960h \
  --dtype float16
```

Open **Apple Models -> wav2vec2-base -> Wav2Vec2 Base Playground**, import the
generated `.aimodel`, and choose a speech recording no longer than five
seconds. The Lab uses AVFoundation to decode, downmix, and resample the clip to
16 kHz mono, pads it to the recipe's `[1, 80000]` input, runs Core AI, and
decodes the `[1, time, 29]` emissions with the upstream CTC label order.

Set both `COREAI_WAV2VEC2_MODEL_PATH` and `COREAI_WAV2VEC2_AUDIO_PATH` to opt
into the real-model transcription test. Chatterbox Turbo remains the Lab's
separate runnable text-to-speech example.

## Speaker Diarization Research

The **Diarization** workspace imports audio or video, builds a waveform, and
synchronizes playback with a speaker-turn timeline. Its in-app turns remain a
deterministic stub until a complete segmentation, embedding, and clustering
runtime is integrated.

`Conversion/Diarization` contains the first proven real-model stage: a pinned
CAM++ speaker encoder converted with `coreai-torch`. Its checkpoint and matching
3D-Speaker source are Apache-2.0. The FP16 asset has 6.85 million source
parameters, occupies about 14.2 MB, and maps six seconds of 80-bin log-Mel
features to a normalized 192-dimensional speaker embedding. A public AMI
meeting smoke test matched 4/4 held-out speaker clips and preserved PyTorch/Core
AI cosine parity above 0.999994.

```bash
cd Conversion/Diarization
uv sync
uv run pytest -q
uv run python export.py --dtype float16 --frames 600 --overwrite
```

This model recognizes whether prepared speech regions belong to the same
speaker; it does not create turn boundaries alone. Two- and four-second CAM++
contracts only matched 2/4 and 3/4 queries respectively, so early live identity
must remain provisional. The preferred license-first batch pipeline adds MIT
Pyannote segmentation 3.0 and repository-owned clustering; the segmentation
checkpoint is gated, so conversion remains blocked until its upstream Hugging
Face contact-sharing terms are explicitly accepted. MIT LS-EEND is the preferred
true-streaming research path. See `Conversion/Diarization/MODEL_SELECTION.md`
and `Conversion/Diarization/TESTING_PLAN.md` for the license matrix, DER/JER,
long-duration, and physical-device promotion gates.

## Asset Inspector

Open any `.aimodel` package to inspect validity, author, license, description,
function names, and compute types without adding the asset to the app bundle.
This works with standalone Apple recipe outputs and individual assets inside
language, diffusion, or segmentation resource folders.

## Chatterbox Workspace

The macOS target embeds a versioned `recipe.json`, four `.aimodel` assets, and a
Hugging Face tokenizer. The recipe is the source of truth for display metadata,
asset paths, native entrypoints, tokenizer location, preferred target, and the
complete generation-capacity contract:

| Asset | Precision | Entrypoints | Role |
| --- | --- | --- | --- |
| T3 embeddings | FP16 | `prefill`, `decode` | Built-in voice conditioning plus text/speech embeddings |
| T3 transformer | mixed INT4/INT8/FP16 | `prefill`, `decode` | Autoregressive speech-token generation with persistent KV caches |
| S3Gen | FP16 | `main` | 256 speech tokens to 512 generated mel frames |
| HiFT vocoder | FP16 | `vocoder` | 80-bin mel frames to 24 kHz waveform audio |

The bundle occupies about 600 MiB on disk and reports 625.1 MB of allocated
model data on the tested Mac. The app validates the manifest and all six native
entrypoints before enabling generation, then persistently caches Core AI
specialization using the recipe's target preference. Chatterbox UI and engine
code no longer enumerate asset filenames or native function names.

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

## Open the Xcode Project

```bash
cd Core-AI-Framework-Lab
open CoreAIFrameworkLab.xcodeproj
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

## Run the Real Fixture Test on an iPhone

`Scripts/run_device_tests.py` runs only the bundled, deterministic Core AI
function-workbench fixture. It accepts one connected, unlocked physical iPhone
or iPad on iOS 27 or newer. Simulators, Macs, locked or disconnected devices,
disabled Developer Mode, stale developer services, and ambiguous device choices
fail before `xcodebuild` starts.

The project keeps code signing disabled by default. The runner first validates
an already-installed development profile and matching private key, then enables
Xcode's automatic selection from local signing assets. It never passes
`-allowProvisioningUpdates` or registers a device, and it does not force a
profile UUID globally onto Swift package targets. The validated profile must
include the selected device and cover both `com.rudrank.CoreAILab` and
`com.rudrank.CoreAILabTests`. A wildcard development profile is sufficient.

```bash
DEVELOPER_DIR=/path/to/Xcode-beta.app/Contents/Developer \
python3 Scripts/run_device_tests.py \
  --team YOUR_TEAM_ID \
  --device YOUR_PHYSICAL_DEVICE_UDID \
  --profile YOUR_INSTALLED_PROFILE_UUID
```

`--device` and `--profile` are optional when exactly one eligible local choice
exists. Use `--dry-run` to validate device and signing discovery and print the
exact command without building, signing, installing, or launching anything.
Each real run writes a new ignored result bundle below `TestResults/` and prints
the JSON test summary produced by `xcresulttool`. Success requires that summary
to attribute exactly one passed, unskipped test to the selected physical iOS
device; an empty or misrouted filtered run fails the harness.

## Current Limitations

- Apple's repository ships export code and runtime utilities, not converted
  model weights. Export remains a local `uv` workflow in this first slice.
- YOLOS object detection, EfficientSAM point segmentation, SAM 3 text
  segmentation, Qwen3 0.6B language generation, and Apple's four diffusion
  presets have dedicated Apple-runtime playgrounds. Wav2Vec2 adds Apple's
  speech-to-text recipe alongside the existing Chatterbox Turbo text-to-speech
  workspace.
- The diarization workspace still uses stub turns. Its CAM++ Core AI recipe
  proves speaker embeddings and enrollment-style matching, not speech boundary
  detection or a complete production diarization pipeline.
- SAM 3 weights are gated by Meta on Hugging Face. Accept the upstream license
  and authenticate with `hf auth login` before export; the Lab never reads or
  stores Hugging Face credentials.
- Projects, imported artifacts, recipe revisions, target profiles, run records,
  and evidence metadata persist across launches. Recipe-backed Runtime Studio
  adapters can record lifecycle and successful timing metrics, but output files,
  imported file bookmarks, conversion jobs, generic benchmark capture, and
  resumable active execution are not wired to those records yet. Interrupted
  runtime records are reconciled as failed when their project is selected.
- The generic function workbench currently generates NDArray inputs only.
  Stateful execution, image-input adaptation, imported fixtures, persisted
  benchmark evidence, and raw-output export remain later Runtime Studio work.
  Integration export generates invocation code, not task-specific
  preprocessing or mutable-state orchestration.
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
