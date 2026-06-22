# Apple Core AI Capability Audit

Status: checked against Apple documentation, Xcode 27 beta, and
`apple/coreai-models` revision `e358c8435679c904687f8070eb95150e36e4b76d`
on June 19, 2026.

## Product boundary

Core AI Lab can provide an LM Studio-style workbench for `.aimodel` assets now:
inspect, specialize, run, compare, benchmark, optimize, and package. Conversion
must remain recipe-driven. A generic visual “convert any PyTorch model” promise
would hide unsupported operations, source rewrites, state contracts, and
target-specific authoring.

## Official capability map

| Area | What the Lab can expose | Important boundary |
| --- | --- | --- |
| Asset inspection | Validate `AIModelAsset`; read/edit metadata; inspect functions, state, tensor descriptors, storage/compute types, and operation distribution; remove derived artifacts. | Statistics can be slow for large assets. Asset inspection does not run inference. |
| Runtime | Specialize assets; load functions; create tensor/image inputs; manage state and output views; run async inference. | Semantic input/output editors still need a recipe or adapter. |
| Specialization and cache | Select compute preferences, check cached models, choose purge policy, share app-group caches, delete entries, and reopen with bookmarks. | OS changes and storage pressure can invalidate or purge cached artifacts. |
| Advanced execution | Concurrent calls, compute streams, pipelined functions, mutable state, and Metal-buffer paths. | Concurrent calls increase intermediate memory; every optimization needs measurement. |
| Benchmarking | Separate specialization, load, setup, inference, host work, throughput, memory, and warm/cold runs. | Default automatic compute selection should remain the baseline. |
| Conversion | Drive `torch.export` plus `coreai-torch`, dynamic shapes, multiple functions, state names, decompositions, custom lowerings, and inline Metal authoring. | Python 3.11+ and compatible PyTorch/Core AI wheels are required. Conversion is not universal. |
| Optimization | Quantization, palettization, sparsity, mixed precision, calibration, and QAT with `coreai-opt`. Weight-only compression can start from an existing `.aimodel` program. | Activation quantization and QAT still require data and the source-model workflow. |
| Debugging | Capture parity, NaN/Inf checks, graph differences, intermediate values, source locations, and hand off to Core AI Debugger. | Apple’s visual debugger is not an embeddable framework; the Lab should launch it rather than clone it. |
| Profiling | Record app timings and launch the Core AI Instruments workflow or debug gauge. | Live captured inputs and some beta debugger paths remain tool-controlled. |
| Packaging | Inspect, edit metadata, package, and ahead-of-time compile from `coreai-build`. | AOT artifacts are architecture-specific and still require residual device specialization. |

Primary references:

- [Core AI](https://developer.apple.com/documentation/coreai/)
- [AIModelAsset](https://developer.apple.com/documentation/coreai/aimodelasset)
- [AIModel](https://developer.apple.com/documentation/coreai/aimodel)
- [Managing specialization and caching](https://developer.apple.com/documentation/coreai/managing-model-specialization-and-caching)
- [Ahead-of-time compilation](https://developer.apple.com/documentation/coreai/compiling-core-ai-models-ahead-of-time)
- [Meet Core AI](https://developer.apple.com/videos/play/wwdc2026/324/)
- [Author and optimize Core AI models](https://developer.apple.com/videos/play/wwdc2026/325/)
- [Integrate Core AI models into an app](https://developer.apple.com/videos/play/wwdc2026/326/)
- [Core AI PyTorch Extensions](https://github.com/apple/coreai-torch)
- [Core AI Optimization](https://apple.github.io/coreai-optimization/)

## `coreai-build` as a Lab backend

The Xcode 27 tool exposes four useful commands:

- `inspect` — inspect source or compiled assets, including JSON output.
- `metadata` — update model metadata and function-argument documentation.
- `package` — package source or compiled assets for a platform and minimum OS.
- `compile` — produce architecture-specific `.aimodelc` assets with compute and reshape hints.

These commands belong behind visible, reproducible jobs. Their full command,
Xcode build, target architecture, input checksum, output checksum, and logs
should be persisted with the project.

The first in-app conversion slice begins applying that evidence rule to Apple's
recipe exporters. It validates a clean checkout at the pinned revision, embeds
the environment checks and typed command in the evidence log, preserves streamed
output, supports cancellation, and discovers only packages created or updated
by the run. Input/output checksums, signed manifests, and packaged project
history remain later milestones. A successful process exit alone does not prove
model parity.

## What `apple/coreai-models` contains

Apple’s repository provides:

- export recipes and a 33-preset registry representing 30 unique models;
- reusable Python authoring primitives;
- Swift runtime products for language, diffusion, segmentation, and object detection;
- command-line runners and benchmarks;
- Core AI authoring and compression skills.

It does not provide model weights or ready-made exported assets. Recipes fetch
weights from Hugging Face, Torch Hub, or other upstream sources. The recipe
repository is BSD-3-Clause; each model keeps its own license, access terms, and
source revision.

Official sources:

- [Repository overview](https://github.com/apple/coreai-models)
- [Model catalog and export commands](https://github.com/apple/coreai-models/blob/e358c8435679c904687f8070eb95150e36e4b76d/models/README.md)
- [Registry source](https://github.com/apple/coreai-models/blob/e358c8435679c904687f8070eb95150e36e4b76d/python/src/coreai_models/model_registry.py)
- [Swift products](https://github.com/apple/coreai-models/blob/e358c8435679c904687f8070eb95150e36e4b76d/Package.swift)

## Verified first integration: YOLOS Tiny

Command:

```bash
uv run models/yolo/export.py \
  --model hustvl/yolos-tiny \
  --dtype float16 \
  --output-dir /tmp/coreai-yolos-export \
  --overwrite
```

Observed result:

| Evidence | Value |
| --- | --- |
| Apple recipe revision | `e358c8435679c904687f8070eb95150e36e4b76d` |
| Resolved Hugging Face source | `95a90f3c189fbfca3bcfc6d7315b9e84d95dc2de` |
| Asset | `yolos-tiny_float16_static.aimodel` |
| Main graph size | 63,404,862 bytes |
| Main graph SHA-256 | `60baa62586aa9daddd674104eeb818619380c523797894de6d18de552756bfdb` |
| Input | Float16 `[1, 3, 512, 512]` |
| Outputs | logits `[1, 100, 92]`, boxes `[1, 100, 4]`, hidden `[1, 1125, 192]` |
| Cold inference | 2.11 seconds |
| Warm inference | 23.7–49 ms |
| Asset license metadata | Apache-2.0 |

The output correctly identified both cats and multiple remotes in the test
image. The emitted 512x512 signature is why the Lab must inspect actual assets
instead of assuming dimensions from prose examples.

## Verified community audio embedding: CAM++

The license-first diarization probe pins the public Apache-2.0
`funasr/campplus` checkpoint at revision
`e4b6ede7ce16997aff4ae69fbca1f0175e2afede`. The matching 3D-Speaker
implementation is also Apache-2.0. Static segment pooling, explicit unbiased
variance, and final inference BatchNorm folding make the 6,848,544-parameter
source architecture convertible through `torch.export` and `coreai-torch`
0.4.0 without a custom lowering.

The verified FP16 asset is about 14.2 MB with input `[1, 600, 80]` log-Mel
frames and output `[1, 192]` normalized speaker embeddings. Core AI/PyTorch
cosine parity stayed above 0.999994 on eight real AMI windows, and
nearest-enrollment matching identified all four speakers. Cached warm inference
measured about 6-8 ms on the tested Mac.

The Lab bundles that audited Apache-2.0 asset and specializes it automatically
in an experimental batch pipeline with repository-owned energy segmentation, a
Kaldi-compatible Accelerate frontend, three-second timeline slices, and
deterministic cosine clustering. A labeled AMI `A → B → A → B` fixture produced
the correct anonymous `1 → 2 → 1 → 2` pattern in 1.872–2.884 seconds across two
runs including decode for 27.06 seconds of audio on the tested Mac. This is a
functional smoke check, not an overlap-aware or production-quality score.

Context remains a real quality boundary: the enrollment smoke fixture matched
only 2/4 queries at two seconds and 3/4 at four seconds. The independent
Pyannote/WeSpeaker/VBx Core ML reference reached 10.42% DER and found 4/4
speakers on AMI `ES2004a`, but that is only a pipeline reference. The preferred
Core AI stack replaces the fallback energy segmenter with MIT Pyannote
segmentation 3.0; it cannot inherit the reference DER until overlap-aware
segmentation and end-to-end RTTM scoring are reproduced.

## Recommended official-example sequence

1. **YOLOS Tiny** — proves a standalone asset and Apple’s object-detection runtime.
2. **EfficientSAM** — adds a resource-folder schema, prompt inputs, masks, and Apple’s segmentation runtime.
3. **Qwen3 0.6B** — adds tokenizers, prefill/decode, mutable cache state, sampling, and Apple’s language runtime.
4. **SAM3 plus Qwen3** — recreates Apple’s multi-model WWDC composition as an opt-in project. SAM3 is gated and large, so it should not be the first-run download.
5. **Stable Diffusion or FLUX** — exercises a multi-asset pipeline, schedulers, tokenizers, sidecar resources, and variant comparison.

Chatterbox remains the custom/community golden project beside these official
recipes. It is valuable precisely because it exercises unsupported-op rewrites,
manual partitioning, audio QA, and a runtime pipeline beyond Apple’s catalog.

## Current beta constraints to expose honestly

- Some custom Metal-kernel and AOT paths can fail in the current beta.
- Dynamic-shape control flow remains model-sensitive.
- Some precision, palette, and sparse combinations can fall back from Neural Engine.
- Metal API Validation can interfere with Core AI execution.
- Debug-gauge input extraction can be unreliable.
- Apple’s Swift model package currently targets iOS 27 and macOS 27, even though the underlying Core AI framework has broader OS-family availability.

These belong in Device Doctor and per-run evidence, not hidden in release notes.
