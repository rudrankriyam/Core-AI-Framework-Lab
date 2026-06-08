# Core AI Framework Notes

Source inspected:

`/Users/rudrank/Downloads/Xcode-beta.app`

Version:

`CFBundleShortVersionString = 27.0`

## Framework Locations

Public framework:

`/Users/rudrank/Downloads/Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/CoreAI.framework`

Readable top-level Swift interface:

`CoreAI.framework/Modules/CoreAI.swiftmodule/arm64e-apple-ios.swiftinterface`

Subframeworks:

`/Users/rudrank/Downloads/Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/SubFrameworks/CoreAIAsset.framework`

`/Users/rudrank/Downloads/Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/SubFrameworks/CoreAIDelegates.framework`

`/Users/rudrank/Downloads/Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/SubFrameworks/CoreAIRuntime.framework`

`/Users/rudrank/Downloads/Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/SubFrameworks/CoreAICompiler.framework`

`/Users/rudrank/Downloads/Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/SubFrameworks/CoreAICommon.framework`

`/Users/rudrank/Downloads/Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/SubFrameworks/CoreAICache.framework`

## Platform Availability

The public Core AI APIs are annotated:

```swift
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
```

Unlike the Xcode 26.5 Foundation Models framework, CoreAI is present for iPhoneOS, AppleTVOS, WatchOS, XROS, and MacOSX device SDKs. Simulator support looks uneven in this first scan: the top-level `CoreAI.framework` was found in device SDK roots, while simulator roots still need more validation before relying on them.

## Top-Level Module

`CoreAI.swiftinterface` is mostly a re-export shell:

```swift
@_exported public import CoreAIDelegates
```

That means most examples can begin with:

```swift
import CoreAI
```

and then use types originally defined in `CoreAIDelegates`, `CoreAIAsset`, and `CoreAIRuntime`.

## Core Concepts

### AIModelAsset

From `CoreAIAsset`:

```swift
public struct AIModelAsset {
    public let url: URL
    public var metadata: AIModelAsset.Metadata { get }
    public static func isValid(at url: URL) -> Bool
    public init(contentsOf url: URL) throws
    public func summary(includingStatistics: Bool) throws -> AIModelAsset.Summary?
    public mutating func removeDerivedArtifacts() throws
    public mutating func updateMetadata(_ updates: (inout AIModelAsset.Metadata) throws -> Void) throws
}
```

This appears to be the file/package inspection layer for Core AI model assets.

### Metadata

`AIModelAsset.Metadata` exposes:

- `author`
- `license`
- `description`
- `creationDate`
- `creatorDefinedMetadata`
- typed subscripts for `String`, `Int`, `Double`, `Bool`, arrays, and dictionaries

The creator-defined value enum supports strings, integers, doubles, booleans, arrays, and dictionaries, with literal conformances.

### Summary

`AIModelAsset.Summary` exposes:

- `functions`
- `storageTypes`
- `computeTypes`
- `operationDistribution`

The function descriptors include names plus input, state, and output descriptors.

### AIModel

From `CoreAIRuntime` and `CoreAIDelegates`:

```swift
public struct AIModel: Sendable {
    public var functionNames: [String] { get }
    public func functionDescriptor(for functionName: String) -> InferenceFunctionDescriptor?
}
```

Additional delegate extensions expose:

```swift
public init(contentsOf modelURL: URL, options: SpecializationOptions = .default) async throws

@discardableResult
public static func specialize(
    contentsOf modelURL: URL,
    options: SpecializationOptions = .default,
    cache: AIModelCache = .default,
    cachePolicy: AIModelCache.Policy = .default
) async throws -> AIModel

public static var deviceArchitectureName: String { get }

public func loadFunction(named functionName: String) throws -> InferenceFunction?
```

### Specialization

`SpecializationOptions` controls compute selection:

```swift
public struct SpecializationOptions: Hashable, Sendable {
    public static let `default`: SpecializationOptions
    public static let cpuOnly: SpecializationOptions
    public init(preferredComputeUnitKind: ComputeUnitKind)
    public var allowedComputeUnitKinds: Set<ComputeUnitKind> { get }
    public var preferredComputeUnitKind: ComputeUnitKind? { get }
    public var expectFrequentReshapes: Bool
}
```

`ComputeUnitKind` cases:

- `cpu`
- `gpu`
- `neuralEngine`

It also exposes:

```swift
public static var availableKinds: Set<ComputeUnitKind> { get }
```

### Model Cache

`AIModelCache` exposes:

- `.default`
- `init?(appGroup:)`
- `model(for:options:)`
- `deleteEntry(referencedBy:)`
- `deleteEntry(for:options:)`
- `deleteEntries(for:)`
- `deleteAll()`

`AIModelCache.Policy` supports purge conditions:

- `storagePressure`
- `sourceAssetChangedOrDeleted`

### Runtime and Inference

`InferenceFunction` exposes:

- `descriptor`
- async `run(inputs:states:outputViews:)`
- dictionary-based async `run(inputs:states:outputViews:)`
- lower-level `encode(inputs:states:outputViews:to:)`

`InferenceValue` supports:

- `ndArray`
- `image`
- pixel buffers

`NDArray` and `NDArrayDescriptor` are the tensor layer. The interface uses new Swift 6.4 experimental features like spans, lifetimes, noncopyable values, and addressable parameters.

## Related New Public Frameworks

Xcode 27 beta also includes:

- `VisualIntelligence.framework`
- `MediaIntelligence.framework`

`VisualIntelligence` currently exposes `SemanticContentDescriptor`, with App Intents integration and labels plus optional pixel-buffer access.

`MediaIntelligence` exposes face grouping, image/video asset types, highlight analysis, key-frame analysis, and a `VideoAnalyzer`.

## Early Interpretation

Core AI is not a drop-in Foundation Models replacement. It looks closer to a lower-level successor or companion to Core ML:

- model asset metadata and summaries
- model specialization and caching
- explicit compute-unit selection
- runtime function loading
- tensor/image inference values
- async inference execution

Foundation Models remains the high-level language model API. Core AI appears to be the lower-level model runtime/asset layer.

