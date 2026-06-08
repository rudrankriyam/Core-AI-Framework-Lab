# Core AI Framework Example

Early examples for Apple's `CoreAI.framework` in Xcode 27 beta.

This repository is intentionally compiler-first. It verifies the public SDK surface, documents the new framework shape, and gives us a small SwiftUI app to grow into real model examples once iOS 27 runtime devices/simulators are ready.

## Requirements

- Xcode 27 beta
- iOS 27.0+ or macOS 27.0+
- Swift 6.4 toolchain from Xcode 27 beta

## What's Inside

- `CoreAILab/` - SwiftUI app target that imports `CoreAI`
- `CoreAILabCore/` - small reusable helpers for Core AI API discovery
- `coreai.md` - notes from the local Xcode 27 SDK interfaces
- `project.yml` - XcodeGen project definition

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

## Current SDK Shape

`CoreAI.framework` is a public framework in Xcode 27 beta, but the top-level Swift module mostly re-exports `CoreAIDelegates`. The usable public API fans out into subframeworks:

- `CoreAIAsset`
- `CoreAIDelegates`
- `CoreAIRuntime`
- `CoreAICompiler`
- `CoreAICommon`
- `CoreAICache`

See `coreai.md` for the current symbol notes.
