import CryptoKit
import Foundation
import Testing
@testable import CoreAILab

struct CoreAIRecipeBundleTests {
    @Test
    func deterministicExportProducesStableManifestAndProvenance() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let exporter = CoreAIRecipeBundleExporter()

        let first = try await exporter.export(
            fixture.draft,
            to: fixture.rootURL.appending(path: "First.recipebundle")
        )
        let second = try await exporter.export(
            fixture.draft,
            to: fixture.rootURL.appending(path: "Second.recipebundle")
        )

        #expect(first.manifest == second.manifest)
        #expect(first.manifestSHA256 == second.manifestSHA256)
        #expect(first.manifest.provenance.sourceRevision == "0123456789abcdef")
        #expect(
            try Data(contentsOf: first.bundleURL.appending(
                path: CoreAIRecipeBundleManifest.fileName
            )) == Data(contentsOf: second.bundleURL.appending(
                path: CoreAIRecipeBundleManifest.fileName
            ))
        )
    }

    @Test
    func canonicalManifestHashIgnoresInventoryOrdering() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let exported = try await CoreAIRecipeBundleExporter().export(
            fixture.draft,
            to: fixture.rootURL.appending(path: "Ordered.recipebundle")
        )
        let reorderedManifest = CoreAIRecipeBundleManifest(
            schemaVersion: exported.manifest.schemaVersion,
            id: exported.manifest.id,
            familyID: exported.manifest.familyID,
            revision: exported.manifest.revision,
            displayName: exported.manifest.displayName,
            summary: exported.manifest.summary,
            recipeManifestPath: exported.manifest.recipeManifestPath,
            provenance: exported.manifest.provenance,
            files: Array(exported.manifest.files.reversed()),
            codeReferences: Array(exported.manifest.codeReferences.reversed())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var reorderedData = try encoder.encode(reorderedManifest)
        reorderedData.append(0x0A)
        try reorderedData.write(
            to: exported.bundleURL.appending(path: CoreAIRecipeBundleManifest.fileName),
            options: .atomic
        )

        let session = try await fixture.importer.importBundle(at: exported.bundleURL)

        #expect(session.summary.manifestSHA256 == exported.manifestSHA256)
    }

    @Test
    func manifestDecoderRejectsUnknownFields() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let encoder = JSONEncoder()
        var topLevel = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(fixture.draftManifest))
                as? [String: Any]
        )
        topLevel["futurePolicy"] = true
        let topLevelData = try JSONSerialization.data(withJSONObject: topLevel)

        #expect(throws: CoreAIRecipeBundleError.self) {
            _ = try JSONDecoder().decode(
                CoreAIRecipeBundleManifest.self,
                from: topLevelData
            )
        }

        var nested = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(fixture.draftManifest))
                as? [String: Any]
        )
        var files = try #require(nested["files"] as? [[String: Any]])
        files[0]["futurePolicy"] = true
        nested["files"] = files
        let nestedData = try JSONSerialization.data(withJSONObject: nested)

        #expect(throws: CoreAIRecipeBundleError.self) {
            _ = try JSONDecoder().decode(
                CoreAIRecipeBundleManifest.self,
                from: nestedData
            )
        }
    }

    @Test
    func publishedSchemaRejectsTrailingPathComponents() throws {
        let repositoryRootURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let schemaData = try Data(contentsOf: repositoryRootURL.appending(
            path: "Documentation/recipe-bundle.schema.json"
        ))
        let schema = try #require(
            JSONSerialization.jsonObject(with: schemaData) as? [String: Any]
        )
        let definitions = try #require(schema["$defs"] as? [String: Any])
        let safePath = try #require(definitions["safeRelativePath"] as? [String: Any])
        let pattern = try #require(safePath["pattern"] as? String)
        let expression = try NSRegularExpression(pattern: pattern)
        func matches(_ value: String) -> Bool {
            expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ) != nil
        }

        #expect(matches("Recipe/recipe.json"))
        #expect(!matches("Recipe/"))
    }

    @Test
    func importedCodeIsLockedUntilExplicitApproval() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let exportResult = try await CoreAIRecipeBundleExporter().export(
            fixture.draft,
            to: fixture.rootURL.appending(path: "Code.recipebundle")
        )
        let session = try await fixture.importer.importBundle(
            at: exportResult.bundleURL,
            expectedFamilyID: "example/audio"
        )

        #expect(session.summary.trustState == .importedUntrusted)
        #expect(await session.codeApprovalState == .approvalRequired)
        do {
            _ = try await session.authorizedCodeURL(for: "authoring.export")
            Issue.record("Expected imported code to remain locked.")
        } catch let error as CoreAIRecipeBundleError {
            #expect(
                error == .codeExecutionNotApproved(referenceID: "authoring.export")
            )
        }

        await session.approveReferencedCodeExecution()
        let codeURL = try await session.authorizedCodeURL(for: "authoring.export")
        #expect(await session.codeApprovalState == .approved)
        #expect(codeURL.lastPathComponent == "export.py")

        await session.revokeReferencedCodeExecutionApproval()
        #expect(await session.codeApprovalState == .approvalRequired)
    }

    @Test
    @MainActor
    func completedImportDoesNotRemainStuckAfterLateCancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let session = CoreAIRecipeBundleSession(
            bundleRootURL: fixture.sourceRootURL,
            manifest: fixture.draftManifest,
            manifestSHA256: String(repeating: "0", count: 64)
        )
        let model = CoreAIRecipeCatalogWorkspaceModel { _ in
            try? await Task.sleep(for: .milliseconds(20))
            return session
        }
        let importTask = Task {
            await model.importBundle(at: fixture.sourceRootURL)
        }
        importTask.cancel()

        await importTask.value

        #expect(model.phase == .imported)
        #expect(model.importedSummary == session.summary)
        #expect(model.codeApprovalState == .notRequired)
        #expect(model.statusMessage.contains("Imported as untrusted"))
    }

    @Test
    func importRejectsPathTraversalBeforeReadingPayloads() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bundleURL = fixture.rootURL.appending(path: "Traversal.recipebundle")
        let manifest = fixture.manifest(
            files: [
                CoreAIRecipeBundleFile(
                    relativePath: "../outside.json",
                    sha256: String(repeating: "0", count: 64),
                    byteCount: 0,
                    role: .recipeManifest
                )
            ],
            recipeManifestPath: "../outside.json"
        )
        try fixture.write(manifest: manifest, to: bundleURL)

        do {
            _ = try await fixture.importer.importBundle(at: bundleURL)
            Issue.record("Expected traversal to be rejected.")
        } catch let error as CoreAIRecipeBundleError {
            guard case .invalidRelativePath = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

#if os(macOS)
    @Test
    func importRejectsSymbolicLinkPayloads() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let exported = try await CoreAIRecipeBundleExporter().export(
            fixture.draft,
            to: fixture.rootURL.appending(path: "Linked.recipebundle")
        )
        let codeURL = exported.bundleURL.appending(path: "Authoring/export.py")
        let outsideURL = fixture.rootURL.appending(path: "outside.py")
        try Data("print('outside')\n".utf8).write(to: outsideURL)
        try FileManager.default.removeItem(at: codeURL)
        try FileManager.default.createSymbolicLink(
            at: codeURL,
            withDestinationURL: outsideURL
        )

        do {
            _ = try await fixture.importer.importBundle(at: exported.bundleURL)
            Issue.record("Expected a symbolic link to be rejected.")
        } catch let error as CoreAIRecipeBundleError {
            guard case .symbolicLink(let path) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(path == "Authoring/export.py")
        }
    }

    @Test
    func importRejectsSymbolicLinkManagedStagingDirectory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let exported = try await CoreAIRecipeBundleExporter().export(
            fixture.draft,
            to: fixture.rootURL.appending(path: "StagingLink.recipebundle")
        )
        let outsideURL = fixture.rootURL.appending(
            path: "OutsideStaging",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: fixture.managedRootURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outsideURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.managedRootURL.appending(path: ".staging"),
            withDestinationURL: outsideURL
        )

        do {
            _ = try await fixture.importer.importBundle(at: exported.bundleURL)
            Issue.record("Expected a symbolic staging directory to be rejected.")
        } catch let error as CoreAIRecipeBundleError {
            #expect(error == .symbolicLink("."))
        }
    }

    @Test
    func exportRejectsDestinationInsideSourceThroughSymlinkAlias() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let exportDirectory = fixture.sourceRootURL.appending(
            path: "Exports",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )
        let sourceAliasURL = fixture.rootURL.appending(path: "SourceAlias")
        try FileManager.default.createSymbolicLink(
            at: sourceAliasURL,
            withDestinationURL: fixture.sourceRootURL
        )

        do {
            _ = try await CoreAIRecipeBundleExporter().export(
                fixture.draft,
                to: sourceAliasURL.appending(path: "Exports/Alias.recipebundle")
            )
            Issue.record("Expected a symlink alias into the source to be rejected.")
        } catch let error as CoreAIRecipeBundleError {
            #expect(error == .destinationInsideSource)
        }
    }
#endif

    @Test
    func importRejectsPayloadHashMismatch() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let exported = try await CoreAIRecipeBundleExporter().export(
            fixture.draft,
            to: fixture.rootURL.appending(path: "Tampered.recipebundle")
        )
        try Data("tampered\n".utf8).write(
            to: exported.bundleURL.appending(path: "Recipe/recipe.json"),
            options: .atomic
        )

        do {
            _ = try await fixture.importer.importBundle(at: exported.bundleURL)
            Issue.record("Expected a hash mismatch to be rejected.")
        } catch let error as CoreAIRecipeBundleError {
            guard case .hashMismatch(let path, _, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(path == "Recipe/recipe.json")
        }
    }

    @Test
    func importRejectsUnexpectedRecipeFamily() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let exported = try await CoreAIRecipeBundleExporter().export(
            fixture.draft,
            to: fixture.rootURL.appending(path: "Family.recipebundle")
        )

        do {
            _ = try await fixture.importer.importBundle(
                at: exported.bundleURL,
                expectedFamilyID: "different/family"
            )
            Issue.record("Expected a family mismatch to be rejected.")
        } catch let error as CoreAIRecipeBundleError {
            #expect(
                error == .familyMismatch(
                    expected: "different/family",
                    actual: "example/audio"
                )
            )
        }
    }

    @Test
    func importRejectsFutureBundleSchemaVersion() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bundleURL = fixture.rootURL.appending(path: "Future.recipebundle")
        let manifest = CoreAIRecipeBundleManifest(
            schemaVersion: CoreAIRecipeBundleManifest.currentSchemaVersion + 1,
            id: "example/audio/demo",
            familyID: "example/audio",
            revision: "0123456789abcdef",
            displayName: "Demo",
            summary: "Future schema fixture",
            recipeManifestPath: "Recipe/recipe.json",
            provenance: fixture.provenance,
            files: []
        )
        try fixture.write(manifest: manifest, to: bundleURL)

        do {
            _ = try await fixture.importer.importBundle(at: bundleURL)
            Issue.record("Expected a future schema to be rejected.")
        } catch let error as CoreAIRecipeBundleError {
            #expect(
                error == .unsupportedSchemaVersion(
                    found: CoreAIRecipeBundleManifest.currentSchemaVersion + 1,
                    supported: CoreAIRecipeBundleManifest.currentSchemaVersion
                )
            )
        }
    }

    @Test
    func manifestRejectsExecutableSourceDisguisedAsData() {
        let fixtureProvenance = CoreAIRecipeBundleProvenance(
            sourceRepository: "https://example.com/repository",
            sourceRevision: "0123456789abcdef",
            license: "MIT",
            author: "Example Authors"
        )
        for executablePath in ["Authoring/export.py", "Authoring/export.bash"] {
            let manifest = CoreAIRecipeBundleManifest(
                id: "example/audio/demo",
                familyID: "example/audio",
                revision: "0123456789abcdef",
                displayName: "Example Audio",
                summary: "Misclassified executable fixture",
                recipeManifestPath: "Recipe/recipe.json",
                provenance: fixtureProvenance,
                files: [
                    CoreAIRecipeBundleFile(
                        relativePath: "Recipe/recipe.json",
                        sha256: String(repeating: "0", count: 64),
                        byteCount: 0,
                        role: .recipeManifest
                    ),
                    CoreAIRecipeBundleFile(
                        relativePath: executablePath,
                        sha256: String(repeating: "1", count: 64),
                        byteCount: 0,
                        role: .data
                    )
                ]
            )

            #expect(throws: CoreAIRecipeBundleError.self) {
                try manifest.validate()
            }
        }
    }

    @Test
    func importRejectsExtensionlessExecutableDisguisedAsData() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bundleURL = fixture.rootURL.appending(path: "HiddenCode.recipebundle")
        let recipeData = Data("{\"schemaVersion\":1}\n".utf8)
        let workerData = Data("#!/bin/sh\necho hidden\n".utf8)
        try FileManager.default.createDirectory(
            at: bundleURL.appending(path: "Recipe"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: bundleURL.appending(path: "Authoring"),
            withIntermediateDirectories: true
        )
        try recipeData.write(to: bundleURL.appending(path: "Recipe/recipe.json"))
        try workerData.write(to: bundleURL.appending(path: "Authoring/worker"))
        let manifest = fixture.manifest(
            files: [
                CoreAIRecipeBundleFile(
                    relativePath: "Recipe/recipe.json",
                    sha256: sha256(recipeData),
                    byteCount: Int64(recipeData.count),
                    role: .recipeManifest
                ),
                CoreAIRecipeBundleFile(
                    relativePath: "Authoring/worker",
                    sha256: sha256(workerData),
                    byteCount: Int64(workerData.count),
                    role: .data
                )
            ],
            recipeManifestPath: "Recipe/recipe.json"
        )
        try fixture.write(manifest: manifest, to: bundleURL)

        do {
            _ = try await fixture.importer.importBundle(at: bundleURL)
            Issue.record("Expected extensionless executable content to be rejected.")
        } catch let error as CoreAIRecipeBundleError {
            #expect(error == .hiddenCodeReference(path: "Authoring/worker"))
        }
    }

    @Test
    func curatedIndexKeepsTrustAndVerificationIndependent() throws {
        let repositoryRootURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRootURL.appending(
            path: "CoreAILab/Resources/Recipes/curated-recipes.json"
        ))
        let index = try CoreAIRecipeCatalog.decodeCurated(data)
        try index.validateReferencedDigests(at: repositoryRootURL)
        let chatterbox = try #require(index.entries.first)

        #expect(chatterbox.trustState == .bundledCurated)
        #expect(chatterbox.verificationState == .fixturesValidated)
        #expect(chatterbox.evidenceReference != nil)
        #expect(chatterbox.verificationNotes.contains("does not claim a hardware"))
        let manifestURL = repositoryRootURL.appending(
            path: chatterbox.recipeManifestReference
        )
        #expect(sha256(try Data(contentsOf: manifestURL)) == chatterbox.recipeManifestSHA256)
        let evidenceReference = try #require(chatterbox.evidenceReference)
        let evidenceSHA256 = try #require(chatterbox.evidenceSHA256)
        #expect(
            sha256(try Data(contentsOf: repositoryRootURL.appending(path: evidenceReference)))
                == evidenceSHA256
        )
    }

    @Test
    func catalogDigestValidationRejectsAlteredRecipeAndEvidence() throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "CoreAIRecipeCatalogDigestTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let recipeURL = rootURL.appending(path: "recipe.json")
        let evidenceURL = rootURL.appending(path: "evidence.json")
        let recipeData = Data("{\"recipe\":true}\n".utf8)
        let evidenceData = Data("{\"fixturesPassed\":true}\n".utf8)
        try recipeData.write(to: recipeURL)
        try evidenceData.write(to: evidenceURL)
        let index = CoreAIRecipeCatalogIndex(
            entries: [
                CoreAIRecipeCatalogEntry(
                    id: "example/catalog-entry",
                    familyID: "example/family",
                    revision: "0123456789abcdef",
                    displayName: "Example",
                    summary: "Digest-bound catalog fixture",
                    recipeManifestReference: "recipe.json",
                    recipeManifestSHA256: sha256(recipeData),
                    trustState: .bundledCurated,
                    verificationState: .fixturesValidated,
                    verificationNotes: "Fixture evidence is bound by digest.",
                    evidenceReference: "evidence.json",
                    evidenceSHA256: sha256(evidenceData)
                )
            ]
        )
        try index.validateReferencedDigests(at: rootURL)

        try Data("{\"recipe\":false}\n".utf8).write(to: recipeURL)
        do {
            try index.validateReferencedDigests(at: rootURL)
            Issue.record("Expected altered recipe bytes to invalidate the catalog.")
        } catch let error as CoreAIRecipeBundleError {
            guard case .hashMismatch(let path, _, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(path == "recipe.json")
        }

        try recipeData.write(to: recipeURL)
        try Data("{\"fixturesPassed\":false}\n".utf8).write(to: evidenceURL)
        do {
            try index.validateReferencedDigests(at: rootURL)
            Issue.record("Expected altered evidence bytes to invalidate the catalog.")
        } catch let error as CoreAIRecipeBundleError {
            guard case .hashMismatch(let path, _, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(path == "evidence.json")
        }
    }

#if os(macOS)
    @Test
    func curatedIndexIsEmbeddedInTheAppBundle() throws {
        let index = try CoreAIRecipeCatalog.loadCurated(bundle: .main)

        #expect(index.entries.map(\.id) == ["resemble/chatterbox-turbo"])
    }
#endif
}

private struct Fixture {
    let rootURL: URL
    let sourceRootURL: URL
    let managedRootURL: URL

    var importer: CoreAIRecipeBundleImporter {
        CoreAIRecipeBundleImporter(managedRootURL: managedRootURL)
    }

    var provenance: CoreAIRecipeBundleProvenance {
        CoreAIRecipeBundleProvenance(
            sourceRepository: "https://example.com/models/audio",
            sourceRevision: "0123456789abcdef",
            license: "MIT",
            author: "Example Authors"
        )
    }

    var draft: CoreAIRecipeBundleDraft {
        CoreAIRecipeBundleDraft(
            sourceRootURL: sourceRootURL,
            id: "example/audio/demo",
            familyID: "example/audio",
            revision: "0123456789abcdef",
            displayName: "Example Audio",
            summary: "Deterministic recipe bundle fixture",
            recipeManifestPath: "Recipe/recipe.json",
            provenance: provenance,
            files: [
                CoreAIRecipeBundleDraftFile(
                    relativePath: "Validation/contracts.json",
                    role: .validationFixture
                ),
                CoreAIRecipeBundleDraftFile(
                    relativePath: "Authoring/export.py",
                    role: .pythonSource
                ),
                CoreAIRecipeBundleDraftFile(
                    relativePath: "Recipe/recipe.json",
                    role: .recipeManifest
                )
            ],
            codeReferences: [
                CoreAIRecipeCodeReference(
                    id: "authoring.export",
                    relativePath: "Authoring/export.py",
                    language: .python,
                    entryPoint: "export:main"
                )
            ]
        )
    }

    var draftManifest: CoreAIRecipeBundleManifest {
        manifest(
            files: [
                CoreAIRecipeBundleFile(
                    relativePath: "Recipe/recipe.json",
                    sha256: String(repeating: "0", count: 64),
                    byteCount: 0,
                    role: .recipeManifest
                )
            ],
            recipeManifestPath: "Recipe/recipe.json"
        )
    }

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "CoreAIRecipeBundleTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        sourceRootURL = rootURL.appending(
            path: "Source",
            directoryHint: .isDirectory
        )
        managedRootURL = rootURL.appending(
            path: "Managed",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: sourceRootURL.appending(path: "Recipe"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sourceRootURL.appending(path: "Validation"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sourceRootURL.appending(path: "Authoring"),
            withIntermediateDirectories: true
        )
        try Data("{\"schemaVersion\":1}\n".utf8).write(
            to: sourceRootURL.appending(path: "Recipe/recipe.json")
        )
        try Data("{\"fixture\":true}\n".utf8).write(
            to: sourceRootURL.appending(path: "Validation/contracts.json")
        )
        try Data("def main():\n    return None\n".utf8).write(
            to: sourceRootURL.appending(path: "Authoring/export.py")
        )
    }

    func manifest(
        files: [CoreAIRecipeBundleFile],
        recipeManifestPath: String
    ) -> CoreAIRecipeBundleManifest {
        CoreAIRecipeBundleManifest(
            id: "example/audio/demo",
            familyID: "example/audio",
            revision: "0123456789abcdef",
            displayName: "Example Audio",
            summary: "Invalid bundle fixture",
            recipeManifestPath: recipeManifestPath,
            provenance: provenance,
            files: files
        )
    }

    func write(manifest: CoreAIRecipeBundleManifest, to bundleURL: URL) throws {
        try FileManager.default.createDirectory(
            at: bundleURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(
            to: bundleURL.appending(path: CoreAIRecipeBundleManifest.fileName)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func sha256(_ data: Data) -> String {
    let digits = Array("0123456789abcdef".utf8)
    let bytes = SHA256.hash(data: data).flatMap { byte in
        [digits[Int(byte >> 4)], digits[Int(byte & 0x0f)]]
    }
    return String(decoding: bytes, as: UTF8.self)
}
