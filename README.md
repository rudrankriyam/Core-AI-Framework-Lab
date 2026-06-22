# Core AI Framework Lab

<p align="center">
  <img src="CoreAILab/Core%20AI%20Lab.icon/Assets/Core-AI-Lab-Icon-1024.png" width="120" alt="Core AI Lab app icon">
</p>

[![Xcode 27 beta](https://img.shields.io/badge/Xcode-27%20beta-147EFB?logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2027%20%7C%20macOS%2027-lightgrey)](https://developer.apple.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A native SwiftUI workbench for discovering, converting, inspecting, running,
benchmarking, and packaging models with Apple's `CoreAI.framework`.

- **Explore** 33 pinned Apple model recipes across language, vision, audio, and
  diffusion.
- **Run** task-specific playgrounds or inspect an arbitrary `.aimodel` through
  the generic Function Workbench.
- **Prove and package** results with project provenance, benchmark evidence,
  physical-device evidence, and verified Swift integration exports.

> [!NOTE]
> Core AI is the asset, specialization, and runtime layer explored here. It is
> not Core ML or `FoundationModels`; only the Qwen adapter bridges through
> `FoundationModels`.

## Contents

- [Quick Start](#quick-start)
- [Workspaces](#workspaces)
- [Common Workflows](#common-workflows)
- [Model Workflows](#model-workflows)
- [For Contributors and Agents](#for-contributors-and-agents)
- [Repository Map](#repository-map)
- [Validation](#validation)
- [Current Boundaries](#current-boundaries)
- [Documentation](#documentation)
- [License](#license)

## Quick Start

1. Select Xcode 27 and confirm the toolchain:

   ```bash
   export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
   xcodebuild -version
   ```

2. Open the checked-in project:

   ```bash
   open CoreAIFrameworkLab.xcodeproj
   ```

3. Choose a shared scheme:

   - `CoreAILabMac` for macOS.
   - `CoreAILab` for a physical iPhone or iPad.

4. Build the macOS app from Terminal:

   ```bash
   xcodebuild -project CoreAIFrameworkLab.xcodeproj \
     -scheme CoreAILabMac \
     -destination 'platform=macOS,arch=arm64' \
     -derivedDataPath ./build/Xcode27 \
     build

   open build/Xcode27/Build/Products/Debug/CoreAILab.app
   ```

## Workspaces

| Surface | Use it for |
| --- | --- |
| **Projects** | Persistent artifacts, provenance, recipe revisions, targets, runs, and evidence. |
| **Apple Models** | Browse 33 pinned Apple recipes and their exact export commands. |
| **Recipes** | Review curated trust metadata or import a verified recipe bundle. |
| **Convert** | Run a pinned Apple exporter on macOS with preflight checks and live logs. |
| **Recipe Studio** | Author and validate recipe and pipeline contracts; it does not execute them. |
| **Chatterbox** | Run the bundled macOS text-to-speech pipeline. |
| **Diarization** | Run the experimental bundled CAM++ speaker-timeline pipeline. |
| **Asset Inspector** | Inspect `.aimodel` metadata, functions, compute types, and cache profiles. |
| **Runtime Studio** | Launch task adapters and optionally record run status and timing. |
| **Device Lab** | Author iPhone deployment profiles and import matching device evidence. |

## Common Workflows

### Run an Apple recipe

1. Open **Apple Models** and choose a recipe.
2. Copy its pinned export command.
3. Export from a local `apple/coreai-models` checkout.
4. Import the `.aimodel` or complete resource folder requested by the adapter.
5. Run it from the model detail or **Runtime Studio**.

Apple recipes are conversion instructions, not bundled weights. The app does
not download models or bypass upstream licenses.

### Inspect, benchmark, and export an asset

1. Open a `.aimodel` in **Asset Inspector**.
2. Select an automatic, CPU-only, GPU-preferred, or Neural-Engine-preferred
   specialization profile.
3. Open **Runtime Studio → Function Workbench**.
4. Generate bounded deterministic NDArray inputs and run a stateless function.
5. Run the benchmark and choose **Export Evidence JSON**.
6. Choose **Export Integration** for a dependency-free Swift package.
7. Run `python3 verify-export.py` inside the exported package.

### Store work in a project

1. Create a project under **Projects**.
2. Import a `.aimodel`, resource folder, or supporting file.
3. Add or correct source provenance.
4. Open stored models in Asset Inspector or Function Workbench.
5. Select the project in Runtime Studio to record future run status and timing.

Imports are staged, hashed, checked for symbolic links, and atomically promoted
into content-addressed storage.

### Convert an Apple recipe on macOS

1. Open **Convert**.
2. Select a pinned recipe, local `coreai-models` checkout, output directory,
   and `uv` executable.
3. Resolve every preflight failure before starting.
4. Review the executable and argument list.
5. Run, monitor, or cancel the conversion.
6. Inspect the output or choose **Store in Project**.

The app passes an executable URL and argument array directly to `Process`; it
does not build a shell command from selected paths.

### Import or author a recipe

1. Use **Recipes** to inspect the curated catalog or import a bundle.
2. Verify its manifest, hashes, declared files, and trust state.
3. Explicitly approve code references when needed. Approval does not execute
   code.
4. Use **Recipe Studio** to edit source, dimensions, state, entrypoints,
   rewrites, and typed pipeline nodes.
5. Resolve validation issues before encoding the contract.

## Model Workflows

The Apple catalog contains 33 recipes pinned to revision
`e358c8435679c904687f8070eb95150e36e4b76d`, matching the Xcode package pin.
Refresh it from a checkout at that revision:

```bash
python3 Scripts/update_apple_model_catalog.py /path/to/coreai-models
```

| Workflow | Import | Boundary |
| --- | --- | --- |
| YOLOS Tiny | Standalone `.aimodel` | Object detection through Apple's runtime package. |
| EfficientSAM / SAM 3 | Exported model resources | Point or text segmentation; SAM 3 requires accepted upstream access. |
| Qwen3 0.6B | Complete resource folder | Uses `CoreAILanguageModel` with a `FoundationModels` session. |
| Stable Diffusion / SD3 / FLUX.2 | Complete resource folder | Local generation; gated models require the user's own authentication. |
| Wav2Vec2 | Standalone `.aimodel` plus audio | Static five-second, 16 kHz mono transcription path. |
| Chatterbox Turbo | Bundled macOS assets | Fixed voice, roughly 600 MiB, up to 253 generated speech tokens. |
| Speaker diarization | Local audio or video | Experimental batch CAM++ path with anonymous speakers and no overlap detection. |

Detailed conversion and evidence commands live in:

- [`Conversion/Chatterbox/README.md`](Conversion/Chatterbox/README.md)
- [`Conversion/Diarization/README.md`](Conversion/Diarization/README.md)

## For Contributors and Agents

- Target: iOS 27 and macOS 27 with Xcode 27 and Swift 6.4.
- Read [`AGENTS.md`](AGENTS.md) before changing code.
- Treat [`PRODUCT.md`](PRODUCT.md) as direction, not shipped behavior.
- Use [`CoreAIFrameworkLab.xcodeproj`](CoreAIFrameworkLab.xcodeproj/) as the
  project source of truth; no project generator is required or supported.
- Verify unfamiliar Core AI APIs against the selected Xcode 27 SDK before use.
- Keep claims measurable: preference is not placement, and cache state is not
  performance evidence.

## Repository Map

| Path | Purpose |
| --- | --- |
| [`CoreAILab/`](CoreAILab/) | SwiftUI app, feature views, workspace models, and resources. |
| [`CoreAILabCore/`](CoreAILabCore/) | Shared runtime, persistence, conversion, recipes, pipelines, and export logic. |
| [`CoreAILabTests/`](CoreAILabTests/) | Swift Testing suites and opt-in integration tests. |
| [`Conversion/`](Conversion/) | Python 3.12 conversion and parity projects. |
| [`Documentation/`](Documentation/) | Recipe-bundle guide and schema. |
| [`Scripts/`](Scripts/) | Catalog, fixture, CI, and physical-device helpers. |
| [`.github/ci/`](.github/ci/) | Hosted and hardware CI boundaries. |

## Validation

Match validation to the change. Documentation-only edits do not need a full
Xcode build.

### macOS app and Swift tests

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

xcodebuild -project CoreAIFrameworkLab.xcodeproj \
  -scheme CoreAILabMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ./build/Xcode27 \
  build

xcodebuild -project CoreAIFrameworkLab.xcodeproj \
  -scheme CoreAILabMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ./build/Xcode27 \
  test
```

### Script tests

```bash
python3 -m unittest discover -s Scripts/tests -p 'test_*.py'
```

### Conversion tests

```bash
cd Conversion/Chatterbox
uv sync
uv run pytest -q

cd ../Diarization
uv sync
uv run pytest -q
```

### Physical iOS fixture

1. Connect and unlock one iOS 27+ device.
2. Confirm Developer Mode and existing local signing assets.
3. Start with a dry run:

   ```bash
   export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

   python3 Scripts/run_device_tests.py \
     --team YOUR_TEAM_ID \
     --device YOUR_PHYSICAL_DEVICE_UDID \
     --profile YOUR_INSTALLED_PROFILE_UUID \
     --dry-run \
     --evidence-json TestResults/iphone-dry-run.json
   ```

4. Remove `--dry-run`, choose a new evidence path, and rerun.
5. Import the resulting JSON into **Device Lab**.

The harness never enables provisioning updates. See
[`.github/ci/README.md`](.github/ci/README.md) for CI and hardware-runner setup.

## Current Boundaries

- A preferred compute unit is a request, not proof of hardware placement.
- A cache hit proves a matching compiled artifact, not faster execution or
  lower memory use.
- Apple catalog entries are recipes; their model weights are not bundled.
- Chatterbox and the audited CAM++ encoder are intentional bundled exceptions.
- Function Workbench supports bounded stateless NDArray inputs, not stateful or
  generic image execution.
- Benchmark evidence records only measured fields; memory, energy, and
  placement remain unavailable when not observed.
- The durable conversion job store exists, but Convert does not yet resume a
  killed process after relaunch.
- Recipe Studio validates contracts but does not execute pipelines or imported
  authoring code.
- Runtime Studio persists status and timing, not imported bookmarks or output
  files.
- Chatterbox has one fixed voice and its model bundle is macOS-only.
- Diarization is batch-only, keeps decoded audio in memory, and cannot model
  overlapping speakers.
- Physical-device, external-model, and gated-model tests are opt-in; default
  tests do not download weights or use credentials.
- Core AI and its converter packages are beta APIs and may change between
  Xcode seeds.

## Documentation

- [`AGENTS.md`](AGENTS.md) — implementation and review rules
- [`PRODUCT.md`](PRODUCT.md) — product direction and design principles
- [`coreai.md`](coreai.md) — locally verified Xcode 27 SDK notes
- [`Documentation/RECIPE_BUNDLES.md`](Documentation/RECIPE_BUNDLES.md) — bundle format and trust boundary
- [`.github/ci/README.md`](.github/ci/README.md) — CI and hardware-runner contract
- [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) — bundled asset licenses

Contributions and corrections are welcome through issues or pull requests.

## License

Core AI Framework Lab is available under the [MIT License](LICENSE).
