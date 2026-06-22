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
                    relativePath: "Authoring/export.py",
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

    @Test
    func curatedIndexKeepsTrustAndVerificationIndependent() throws {
        let repositoryRootURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRootURL.appending(
            path: "CoreAILab/Resources/Recipes/curated-recipes.json"
        ))
        let index = try CoreAIRecipeCatalog.decodeCurated(data)
        let chatterbox = try #require(index.entries.first)

        #expect(chatterbox.trustState == .bundledCurated)
        #expect(chatterbox.verificationState == .fixturesValidated)
        #expect(chatterbox.evidenceReference == nil)
        #expect(chatterbox.verificationNotes.contains("does not claim a hardware"))
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
