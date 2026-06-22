import Foundation
import Testing
@testable import CoreAILab

struct CoreAIRecipeManifestTests {
#if os(macOS)
    @Test
    func bundledChatterboxManifestMatchesThePortableFixture() throws {
        let bundled = try ChatterboxBundledRecipe(bundle: .main).contract.manifest

        #expect(bundled == ChatterboxRecipeFixture.manifest)
    }
#endif

    @Test
    func chatterboxFixtureValidatesAndRoundTrips() throws {
        let manifest = ChatterboxRecipeFixture.manifest
        try manifest.validate()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(manifest)
        let decoded = try JSONDecoder().decode(CoreAIRecipeManifest.self, from: encoded)

        #expect(decoded == manifest)
        #expect(decoded.schemaVersion == CoreAIRecipeManifest.currentSchemaVersion)
        #expect(decoded.targets.allSatisfy {
            $0.schemaVersion == CoreAITargetManifest.currentSchemaVersion
        })
        #expect(decoded.artifacts.allSatisfy {
            $0.schemaVersion == CoreAIArtifactManifest.currentSchemaVersion
        })
        #expect(
            decoded.pipeline.schemaVersion
                == CoreAIRecipePipelineManifest.currentSchemaVersion
        )
        #expect(decoded.capacity.schemaVersion == CoreAICapacityManifest.currentSchemaVersion)
    }

    @Test
    func manifestRejectsUnsafeArtifactPaths() throws {
        let bundled = ChatterboxRecipeFixture.manifest
        let firstArtifact = try #require(bundled.artifacts.first)
        let unsafeArtifact = CoreAIArtifactManifest(
            id: firstArtifact.id,
            displayName: firstArtifact.displayName,
            kind: firstArtifact.kind,
            relativePath: "../outside",
            precision: firstArtifact.precision,
            requiredEntrypoints: firstArtifact.requiredEntrypoints
        )
        let manifest = replacingFirstArtifact(in: bundled, with: unsafeArtifact)

        #expect(throws: CoreAIManifestValidationError.self) {
            try manifest.validate()
        }
    }

    @Test
    func manifestRejectsFutureSchemaVersions() throws {
        let bundled = ChatterboxRecipeFixture.manifest
        let manifest = CoreAIRecipeManifest(
            schemaVersion: CoreAIRecipeManifest.currentSchemaVersion + 1,
            id: bundled.id,
            revision: bundled.revision,
            displayName: bundled.displayName,
            summary: bundled.summary,
            systemImage: bundled.systemImage,
            source: bundled.source,
            defaultTargetID: bundled.defaultTargetID,
            targets: bundled.targets,
            artifacts: bundled.artifacts,
            pipeline: bundled.pipeline,
            capacity: bundled.capacity
        )

        #expect(throws: CoreAIManifestValidationError.self) {
            try manifest.validate()
        }
    }

    @Test
    func manifestRejectsUnknownEntrypointMappings() throws {
        let bundled = ChatterboxRecipeFixture.manifest
        var stages = bundled.pipeline.stages
        let firstStage = try #require(stages.first)
        stages[0] = CoreAIRecipePipelineStageManifest(
            id: firstStage.id,
            displayName: firstStage.displayName,
            detail: firstStage.detail,
            artifactID: firstStage.artifactID,
            entrypoints: ["prefill": "not-in-the-asset"]
        )
        let manifest = CoreAIRecipeManifest(
            id: bundled.id,
            revision: bundled.revision,
            displayName: bundled.displayName,
            summary: bundled.summary,
            systemImage: bundled.systemImage,
            source: bundled.source,
            defaultTargetID: bundled.defaultTargetID,
            targets: bundled.targets,
            artifacts: bundled.artifacts,
            pipeline: CoreAIRecipePipelineManifest(
                experience: bundled.pipeline.experience,
                tokenizerArtifactID: bundled.pipeline.tokenizerArtifactID,
                stages: stages
            ),
            capacity: bundled.capacity
        )

        #expect(throws: CoreAIManifestValidationError.self) {
            try manifest.validate()
        }
    }

    @Test
    func chatterboxContractMapsAssetsEntrypointsTargetAndCapacity() throws {
        let recipe = try ChatterboxRecipeFixture.contract()

        #expect(recipe.target.id == "mac-gpu")
        #expect(recipe.target.preferredComputeUnit == .gpu)
        #expect(recipe.tokenizerArtifact.relativePath == "tokenizer")
        #expect(
            try recipe.resolvedStage(.t3Embeddings).artifact.relativePath
                == "ChatterboxTurboT3Embeddings.aimodel"
        )
        #expect(
            try recipe.resolvedStage(.t3Transformer).entrypoint(for: .decode)
                == "decode"
        )
        #expect(try recipe.resolvedStage(.s3gen).entrypoint(for: .generateMel) == "main")
        #expect(
            try recipe.resolvedStage(.vocoder).entrypoint(for: .synthesizeWaveform)
                == "vocoder"
        )
        #expect(recipe.capacity.maximumTextTokens == 256)
        #expect(recipe.capacity.maximumSpeechTokens == 253)
        #expect(recipe.capacity.maximumContextLength == 768)
        #expect(recipe.capacity.generatedMelFrameCount == 512)
        #expect(recipe.capacity.sampleRate == 24_000)
        #expect(recipe.capacity.requiresStopToken)
    }

    @Test
    func chatterboxCapacityRejectsUnboundedValuesInsteadOfOverflowing() {
        let capacity = ChatterboxRecipeFixture.capacity(
            maximumGeneratedTokens: .max
        )

        #expect(throws: CoreAIManifestValidationError.self) {
            _ = try ChatterboxResolvedCapacity(manifest: capacity)
        }
    }

    @Test
    func melCapacityUsesTheFullSpeechTokenBuffer() throws {
        let capacity = ChatterboxRecipeFixture.capacity(
            maximumGeneratedTokens: 200,
            speechTokenBufferCount: 256,
            endSilenceTokenCount: 3,
            generatedMelFrameCount: 512
        )

        let resolved = try ChatterboxResolvedCapacity(manifest: capacity)

        #expect(resolved.maximumSpeechTokens == 200)
        #expect(resolved.generatedMelFrameCount == 512)
    }

    @Test
    func chatterboxStagesRequireExactEntrypointRoles() throws {
        let fixture = ChatterboxRecipeFixture.manifest
        var stages = fixture.pipeline.stages
        let first = try #require(stages.first)
        stages[0] = CoreAIRecipePipelineStageManifest(
            id: first.id,
            displayName: first.displayName,
            detail: first.detail,
            artifactID: first.artifactID,
            entrypoints: [
                "prefill": "prefill",
                "decode": "prefill",
                "extra": "decode"
            ]
        )
        let manifest = replacingPipeline(
            in: fixture,
            with: CoreAIRecipePipelineManifest(
                experience: fixture.pipeline.experience,
                tokenizerArtifactID: fixture.pipeline.tokenizerArtifactID,
                stages: stages
            )
        )

        #expect(throws: CoreAIManifestValidationError.self) {
            _ = try ChatterboxRecipeContract(manifest: manifest)
        }
    }

    @Test
    func bundledRecipeRejectsSymlinkedArtifactComponents() throws {
        let parent = FileManager.default.temporaryDirectory.appending(
            path: "ChatterboxRecipeSymlink-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appending(path: "Chatterbox", directoryHint: .isDirectory)
        let outside = parent.appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(ChatterboxRecipeFixture.manifest).write(
            to: root.appending(path: "recipe.json")
        )
        let tokenizer = root.appending(
            path: "tokenizer",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: tokenizer,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: tokenizer.appending(path: "escape"),
            withDestinationURL: outside
        )

        do {
            _ = try ChatterboxBundledRecipe(rootURL: root)
            Issue.record("Expected an unsafe-resource-path error")
        } catch ChatterboxCoreAIError.unsafeResourcePath {
            // Expected: nested symlinks must not be followed by downstream loaders.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func replacingFirstArtifact(
        in manifest: CoreAIRecipeManifest,
        with artifact: CoreAIArtifactManifest
    ) -> CoreAIRecipeManifest {
        var artifacts = manifest.artifacts
        artifacts[0] = artifact
        return CoreAIRecipeManifest(
            id: manifest.id,
            revision: manifest.revision,
            displayName: manifest.displayName,
            summary: manifest.summary,
            systemImage: manifest.systemImage,
            source: manifest.source,
            defaultTargetID: manifest.defaultTargetID,
            targets: manifest.targets,
            artifacts: artifacts,
            pipeline: manifest.pipeline,
            capacity: manifest.capacity
        )
    }

    private func replacingPipeline(
        in manifest: CoreAIRecipeManifest,
        with pipeline: CoreAIRecipePipelineManifest
    ) -> CoreAIRecipeManifest {
        CoreAIRecipeManifest(
            id: manifest.id,
            revision: manifest.revision,
            displayName: manifest.displayName,
            summary: manifest.summary,
            systemImage: manifest.systemImage,
            source: manifest.source,
            defaultTargetID: manifest.defaultTargetID,
            targets: manifest.targets,
            artifacts: manifest.artifacts,
            pipeline: pipeline,
            capacity: manifest.capacity
        )
    }
}
