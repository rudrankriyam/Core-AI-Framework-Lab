import CoreAI
import CryptoKit
import Foundation
import Testing
@testable import CoreAILab

struct CoreAIIntegrationExportTests {
    @Test
    func manifestRoundTripsWithoutSourcePathOrBookmarkData() throws {
        let manifest = CoreAIExportManifest(
            package: .init(
                name: "FixtureIntegration",
                productName: "FixtureIntegration",
                targetName: "FixtureIntegration",
                swiftToolsVersion: "6.4",
                generatedSourceRelativePath: "Sources/FixtureIntegration/Fixture.swift",
                resourcesRelativePath: "Sources/FixtureIntegration/Resources"
            ),
            artifact: .init(
                relativePath: "Sources/FixtureIntegration/Resources/fixture.aimodel",
                sha256: String(repeating: "a", count: 64),
                byteCount: 42
            ),
            report: report(at: URL(filePath: "/private/source/fixture.aimodel")),
            specializationConfiguration: .init(profile: .preferGPU),
            contracts: [tensorContract(named: "main")]
        )

        let data = try JSONEncoder().encode(manifest)
        #expect(try JSONDecoder().decode(CoreAIExportManifest.self, from: data) == manifest)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("/private/source"))
        #expect(!json.localizedCaseInsensitiveContains("bookmark"))
        #expect(manifest.schemaVersion == 2)
        #expect(manifest.package.targetName == "FixtureIntegration")
        #expect(manifest.specialization.profile == "preferGPU")
        #expect(manifest.specialization.preferredCompute == "gpu")
    }

    @Test
    func generatorSanitizesReservedWordsAndDeterministicCollisions() {
        let generator = CoreAISwiftInvocationGenerator()
        let identifiers = generator.methodIdentifiers(
            for: ["foo_bar", "class", "foo-bar", "2decode", "precedencegroup"]
        )

        #expect(identifiers["class"] == "runClass")
        #expect(identifiers["2decode"] == "run2decode")
        #expect(identifiers["foo-bar"] == "fooBar")
        #expect(identifiers["foo_bar"] == "fooBar_2")
        #expect(identifiers["precedencegroup"] == "runPrecedencegroup")
        #expect(generator.typeIdentifier(for: "42 strange-model.aimodel") == "Model42StrangeModel")
    }

    @Test
    func destinationInsideTheSourceIsRejectedBeforeMutation() async throws {
        let sourceParent = temporaryDirectory()
        let sourceURL = sourceParent.appending(
            path: "nested.aimodel",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: sourceParent) }
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: sourceURL.appending(path: "main.mlirb"))

        do {
            _ = try await CoreAIIntegrationExporter().export(
                report: report(at: sourceURL),
                contracts: [tensorContract(named: "main")],
                specializationConfiguration: .init(profile: .automatic),
                destinationParentURL: sourceURL
            )
            Issue.record("Expected a destination within the source to be rejected.")
        } catch CoreAIIntegrationExportError.destinationInsideSource {
            // Expected.
        }

        #expect(
            try FileManager.default.contentsOfDirectory(atPath: sourceURL.path)
                == ["main.mlirb"]
        )
    }

    @Test
    func generatorUsesExactFunctionStringsAndOmitsUnsupportedMethods() {
        let generator = CoreAISwiftInvocationGenerator()
        let supported = tensorContract(named: "decode-token")
        let unsupported = imageContract(named: "class")
        let stateful = statefulContract(named: "decode")
        let descriptorless = descriptorlessContract(named: "missing-descriptor")
        let output = generator.generate(
            assetName: "demo.aimodel",
            contracts: [unsupported, supported, stateful, descriptorless]
        )

        #expect(output.source.contains("public actor DemoCoreAIModel"))
        #expect(output.source.contains("public enum DemoCoreAIModelError"))
        #expect(!output.source.contains("GeneratedCoreAIError"))
        #expect(output.source.contains("func decodeToken"))
        #expect(output.source.contains("loadFunction(named: \"decode-token\")"))
        #expect(!output.source.contains("func runClass"))
        #expect(!output.source.contains("func decode("))
        #expect(!output.source.contains("func missingDescriptor"))
        #expect(unsupported.generatedRuntimeUnsupportedReason == "Image input")
        #expect(stateful.generatedRuntimeUnsupportedReason?.contains("mutable") == true)
        #expect(
            descriptorless.generatedRuntimeUnsupportedReason
                == "Core AI did not provide a descriptor for this function."
        )
    }

    @Test
    func exportIsDeterministicAndCollisionLeavesNoTemporaryPackage() async throws {
        let sourceURL = try fixtureURL()
        let firstParent = temporaryDirectory()
        let secondParent = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstParent)
            try? FileManager.default.removeItem(at: secondParent)
        }
        try FileManager.default.createDirectory(at: firstParent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondParent, withIntermediateDirectories: true)
        let exporter = CoreAIIntegrationExporter()
        let sourceReport = report(at: sourceURL)
        let contracts = [tensorContract(named: "main")]

        let first = try await exporter.export(
            report: sourceReport,
            contracts: contracts,
            specializationConfiguration: .init(profile: .automatic),
            destinationParentURL: firstParent
        )
        let second = try await exporter.export(
            report: sourceReport,
            contracts: contracts,
            specializationConfiguration: .init(profile: .automatic),
            destinationParentURL: secondParent
        )

        #expect(first.manifest == second.manifest)
        #expect(first.manifest.artifact.byteCount > 0)
        #expect(first.manifest.artifact.sha256.count == 64)
        #expect(try packageSnapshot(at: first.packageURL) == packageSnapshot(at: second.packageURL))
        let targetName = first.manifest.package.targetName
        let targetURL = first.packageURL.appending(path: "Sources/\(targetName)")
        let resourcesURL = targetURL.appending(path: "Resources")
        let firstSource = try String(
            contentsOf: targetURL.appending(path: "CoreAILabTensorFixtureCoreAIModel.swift"),
            encoding: .utf8
        )
        #expect(!firstSource.contains("CoreAILabCore"))
        let packageManifest = try String(
            contentsOf: first.packageURL.appending(path: "Package.swift"),
            encoding: .utf8
        )
        #expect(packageManifest.contains(".library("))
        #expect(packageManifest.contains("resources: [.copy(\"Resources\")]"))
        #expect(!packageManifest.contains(".package("))
        let checksums = try JSONDecoder().decode(
            CoreAIExportChecksumManifest.self,
            from: Data(contentsOf: first.packageURL.appending(path: "coreai-checksums.json"))
        )
        #expect(checksums.schemaVersion == 1)
        #expect(
            checksums.files.map(\.relativePath)
                == checksums.files.map(\.relativePath).sorted(
                    by: CoreAIExportPath.isOrderedBefore
                )
        )
        #expect(checksums.files.contains { $0.relativePath == "Package.swift" })
        #expect(checksums.files.contains { $0.relativePath == "verify-export.py" })
        #expect(checksums.files.contains { $0.relativePath == "README.md" })
        #expect(
            checksums.files.contains {
                $0.relativePath.hasSuffix("/Resources/coreai-export.json")
            }
        )
        #expect(
            checksums.files.contains {
                $0.relativePath.hasSuffix("/Resources/THIRD_PARTY_NOTICES.md")
            }
        )
        #expect(checksums.files.contains { $0.relativePath.hasSuffix("/main.mlirb") })
        #expect(!checksums.files.contains { $0.relativePath == "coreai-checksums.json" })
        let notices = try String(
            contentsOf: resourcesURL.appending(path: "THIRD_PARTY_NOTICES.md"),
            encoding: .utf8
        )
        #expect(notices.contains("Reported license: MIT"))
        let resourceAccessor = try String(
            contentsOf: targetURL.appending(path: "CoreAILabTensorFixtureCoreAIModelResources.swift"),
            encoding: .utf8
        )
        #expect(resourceAccessor.contains("static func loadBundled"))
        #expect(resourceAccessor.contains("Bundle.module.resourceURL"))
        let compileScript = try String(
            contentsOf: first.packageURL.appending(path: "compile-model.sh"),
            encoding: .utf8
        )
        #expect(compileScript.contains("--platform iOS"))
        #expect(compileScript.contains("--platform macOS"))
        #expect(compileScript.contains("--min-deployment-version 27.0"))
        #expect(!compileScript.contains("--preferred-compute"))
        #expect(compileScript.contains(first.manifest.artifact.relativePath))
        let verifier = try String(
            contentsOf: first.packageURL.appending(path: "verify-export.py"),
            encoding: .utf8
        )
        #expect(verifier.contains("--disable-automatic-resolution"))
        #expect(verifier.contains("verify_checksums(files)"))
        #expect(!verifier.contains("xcrun\", \"coreai-build"))

        do {
            _ = try await exporter.export(
                report: sourceReport,
                contracts: contracts,
                specializationConfiguration: .init(profile: .automatic),
                destinationParentURL: firstParent
            )
            Issue.record("Expected an existing destination to reject export.")
        } catch CoreAIIntegrationExportError.destinationExists {
            // Expected.
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: firstParent.path).count == 1)
    }

    @Test
    func symbolicLinkIsRejectedAndFailedExportIsCleanedUp() async throws {
        let sourceParent = temporaryDirectory()
        let sourceURL = sourceParent.appending(path: "linked.aimodel", directoryHint: .isDirectory)
        let destinationParent = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceParent)
            try? FileManager.default.removeItem(at: destinationParent)
        }
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: sourceURL.appending(path: "main.mlirb"))
        try FileManager.default.createSymbolicLink(
            at: sourceURL.appending(path: "escape"),
            withDestinationURL: URL(filePath: "/tmp")
        )

        do {
            _ = try await CoreAIIntegrationExporter().export(
                report: report(at: sourceURL),
                contracts: [tensorContract(named: "main")],
                specializationConfiguration: .init(profile: .automatic),
                destinationParentURL: destinationParent
            )
            Issue.record("Expected symbolic-link rejection.")
        } catch CoreAIIntegrationExportError.symbolicLink(let path) {
            #expect(path == "escape")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: destinationParent.path).isEmpty)
    }

    @Test
    func canceledExportLeavesNoPackageOrTemporaryDirectory() async throws {
        let destinationParent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destinationParent) }
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        let (gate, continuation) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            _ = await gate.first(where: { _ in true })
            return try await CoreAIIntegrationExporter().export(
                report: report(at: try fixtureURL()),
                contracts: [tensorContract(named: "main")],
                specializationConfiguration: .init(profile: .automatic),
                destinationParentURL: destinationParent
            )
        }

        task.cancel()
        continuation.yield()
        continuation.finish()
        do {
            _ = try await task.value
            Issue.record("Expected export cancellation.")
        } catch is CancellationError {
            // Expected.
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: destinationParent.path).isEmpty)
    }

    @Test
    func sourceMutationAfterSnapshotIsRejectedAndCleanedUp() async throws {
        let sourceParent = temporaryDirectory()
        let sourceURL = sourceParent.appending(path: "mutable.aimodel", directoryHint: .isDirectory)
        let sourceFileURL = sourceURL.appending(path: "main.mlirb")
        let destinationParent = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceParent)
            try? FileManager.default.removeItem(at: destinationParent)
        }
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        try Data("before".utf8).write(to: sourceFileURL)
        let exporter = CoreAIIntegrationExporter(sourceSnapshotHook: {
            try Data("after".utf8).write(to: sourceFileURL, options: .atomic)
        })

        do {
            _ = try await exporter.export(
                report: report(at: sourceURL),
                contracts: [tensorContract(named: "main")],
                specializationConfiguration: .init(profile: .automatic),
                destinationParentURL: destinationParent
            )
            Issue.record("Expected source mutation to invalidate the export snapshot.")
        } catch CoreAIIntegrationExportError.sourceChanged(let path) {
            #expect(path == "main.mlirb")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: destinationParent.path).isEmpty)
    }

    #if os(macOS)
    @Test
    func checksumVerifierRejectsResourceTampering() async throws {
        let destinationParent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destinationParent) }
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        let result = try await CoreAIIntegrationExporter().export(
            report: report(at: try fixtureURL()),
            contracts: [tensorContract(named: "main")],
            specializationConfiguration: .init(profile: .automatic),
            destinationParentURL: destinationParent
        )
        let noticesURL = result.packageURL.appending(
            path: "Sources/\(result.manifest.package.targetName)/Resources/THIRD_PARTY_NOTICES.md"
        )
        try Data("tampered".utf8).write(to: noticesURL, options: .atomic)

        let outcome = try runExecutableAllowingFailure(
            at: URL(filePath: "/usr/bin/python3"),
            arguments: [
                result.packageURL.appending(path: "verify-export.py").path,
                "--structure-only",
            ]
        )
        #expect(outcome.status != 0)
        #expect(outcome.output.contains("checksum mismatch:"))
        #expect(outcome.output.contains("THIRD_PARTY_NOTICES.md"))
    }

    @Test
    func verifierRejectsUnexpectedPackageResolved() async throws {
        let destinationParent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destinationParent) }
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        let result = try await CoreAIIntegrationExporter().export(
            report: report(at: try fixtureURL()),
            contracts: [tensorContract(named: "main")],
            specializationConfiguration: .init(profile: .automatic),
            destinationParentURL: destinationParent
        )
        try Data("{}\n".utf8).write(
            to: result.packageURL.appending(path: "Package.resolved"),
            options: .atomic
        )

        let outcome = try runVerifierStructureOnly(in: result.packageURL)
        #expect(outcome.status != 0)
        #expect(outcome.output.contains("unexpected package file: Package.resolved"))
    }

    @Test
    func verifierRejectsWhitespaceObfuscatedDependencyAfterChecksumRecalculation() async throws {
        let destinationParent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destinationParent) }
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        let result = try await CoreAIIntegrationExporter().export(
            report: report(at: try fixtureURL()),
            contracts: [tensorContract(named: "main")],
            specializationConfiguration: .init(profile: .automatic),
            destinationParentURL: destinationParent
        )
        let packageURL = result.packageURL.appending(path: "Package.swift")
        var packageSource = try String(contentsOf: packageURL, encoding: .utf8)
        packageSource = packageSource.replacing(
            "    targets: [",
            with: """
                    dependencies : [
                        .package (url: "https://example.invalid/dependency.git", from: "1.0.0"),
                    ],
                    targets: [
                """
        )
        let packageData = Data(packageSource.utf8)
        try packageData.write(to: packageURL, options: .atomic)
        try updateChecksum(for: "Package.swift", data: packageData, in: result.packageURL)

        let outcome = try runVerifierStructureOnly(in: result.packageURL)
        #expect(outcome.status != 0)
        #expect(
            outcome.output.contains(
                "Package.swift does not exactly match the generated dependency-free template"
            )
        )
    }

    @Test
    func verifierRejectsPluginTargetAndFormattingMutationsAfterChecksumRecalculation() async throws {
        let destinationParent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destinationParent) }
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        let result = try await CoreAIIntegrationExporter().export(
            report: report(at: try fixtureURL()),
            contracts: [tensorContract(named: "main")],
            specializationConfiguration: .init(profile: .automatic),
            destinationParentURL: destinationParent
        )
        let packageURL = result.packageURL.appending(path: "Package.swift")
        let original = try String(contentsOf: packageURL, encoding: .utf8)
        let mutations = [
            original.replacing(".target(", with: ".target ("),
            original.replacing(
                "resources: [.copy(\"Resources\")]",
                with: """
                    resources: [.copy("Resources")],
                    plugins : [.plugin (name: "MutatedPlugin")]
                    """
            ),
            original.replacing(
                "resources: [.copy(\"Resources\")]",
                with: """
                    resources: [.copy("Resources")],
                    swiftSettings : [.define ("MUTATED_TARGET")]
                    """
            ),
        ]

        for packageSource in mutations {
            let packageData = Data(packageSource.utf8)
            try packageData.write(to: packageURL, options: .atomic)
            try updateChecksum(for: "Package.swift", data: packageData, in: result.packageURL)

            let outcome = try runVerifierStructureOnly(in: result.packageURL)
            #expect(outcome.status != 0)
            #expect(
                outcome.output.contains(
                    "Package.swift does not exactly match the generated dependency-free template"
                )
            )
        }
    }

    @Test
    func decomposedUnicodePathsNormalizeAndVerifyWithUTF8Ordering() async throws {
        let sourceParent = temporaryDirectory()
        let sourceURL = sourceParent.appending(path: "unicode.aimodel", directoryHint: .isDirectory)
        let destinationParent = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceParent)
            try? FileManager.default.removeItem(at: destinationParent)
        }
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        let decomposedName = "cafe\u{301}.bin"
        try Data("accent".utf8).write(to: sourceURL.appending(path: decomposedName))
        try Data("ascii".utf8).write(to: sourceURL.appending(path: "z.bin"))

        let result = try await CoreAIIntegrationExporter().export(
            report: report(at: sourceURL),
            contracts: [tensorContract(named: "main")],
            specializationConfiguration: .init(profile: .automatic),
            destinationParentURL: destinationParent
        )
        let checksums = try checksumManifest(in: result.packageURL)
        let paths = checksums.files.map(\.relativePath)
        #expect(paths == paths.sorted(by: CoreAIExportPath.isOrderedBefore))
        #expect(paths.contains { $0.hasSuffix("/caf\u{e9}.bin") })
        #expect(
            paths.allSatisfy {
                Array($0.utf8)
                    == Array($0.precomposedStringWithCanonicalMapping.utf8)
            }
        )

        let outcome = try runVerifierStructureOnly(in: result.packageURL)
        #expect(outcome.status == 0)
        #expect(outcome.output.contains("Core AI integration export verified."))
    }
    #endif

    @Test
    func compileScriptUsesOnlySupportedComputeFlags() {
        let generator = CoreAIAheadOfTimeCompileScriptGenerator()
        let gpu = generator.generate(
            assetRelativePath: "Resources/model.aimodel",
            configuration: .init(profile: .preferGPU)
        )
        let neuralEngine = generator.generate(
            assetRelativePath: "Resources/model.aimodel",
            configuration: .init(profile: .preferNeuralEngine)
        )
        let cpu = generator.generate(
            assetRelativePath: "Resources/model.aimodel",
            configuration: .init(profile: .cpuOnly)
        )
        let reshaping = generator.generate(
            assetRelativePath: "Resources/model.aimodel",
            configuration: .init(profile: .automatic, expectFrequentReshapes: true)
        )

        #expect(gpu.contains("--preferred-compute gpu"))
        #expect(neuralEngine.contains("--preferred-compute neural-engine"))
        #expect(!cpu.contains("--preferred-compute"))
        #expect(cpu.contains("Pass .cpuOnly"))
        #expect(reshaping.contains("--expect-frequent-reshapes"))
    }

    @Test
    func generatedRuntimeDefaultsToTheSelectedSpecializationProfile() {
        let generator = CoreAISwiftInvocationGenerator()
        let contract = tensorContract(named: "main")

        let cpu = generator.generate(
            assetName: "cpu.aimodel",
            contracts: [contract],
            specializationConfiguration: .init(profile: .cpuOnly)
        ).source
        let gpu = generator.generate(
            assetName: "gpu.aimodel",
            contracts: [contract],
            specializationConfiguration: .init(profile: .preferGPU)
        ).source

        #expect(cpu.contains("var options = .cpuOnly"))
        #expect(gpu.contains("var options = SpecializationOptions(preferredComputeUnitKind: .gpu)"))
        #expect(cpu.contains("options: SpecializationOptions? = nil"))
    }

    @Test
    func generatedRuntimeCarriesTheFrequentReshapeDefault() {
        let source = CoreAISwiftInvocationGenerator().generate(
            assetName: "dynamic.aimodel",
            contracts: [tensorContract(named: "main")],
            specializationConfiguration: .init(
                profile: .automatic,
                expectFrequentReshapes: true
            )
        ).source

        #expect(source.contains("options.expectFrequentReshapes = true"))
    }

    #if os(macOS)
    @Test
    func compileScriptHasValidShellSyntax() throws {
        let script = CoreAIAheadOfTimeCompileScriptGenerator().generate(
            assetRelativePath: "Resources/model's fixture.aimodel",
            configuration: .init(profile: .cpuOnly, expectFrequentReshapes: true)
        )
        let directory = temporaryDirectory()
        let scriptURL = directory.appending(path: "compile-model.sh")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(script.utf8).write(to: scriptURL)

        _ = try runExecutable(
            at: URL(filePath: "/bin/sh"),
            arguments: ["-n", scriptURL.path]
        )
    }

    @Test
    func generatedSourceTypeChecksAgainstTheInstalledCoreAISDK() throws {
        let source = CoreAISwiftInvocationGenerator().generate(
            assetName: "fixture.aimodel",
            contracts: [
                tensorContract(named: "main"),
                tensorContract(named: "precedencegroup"),
            ],
            specializationConfiguration: .init(profile: .preferGPU)
        ).source
        let directory = temporaryDirectory()
        let sourceURL = directory.appending(path: "Generated.swift")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(source.utf8).write(to: sourceURL)

        let sdkPath = try runXcrun(arguments: ["--sdk", "macosx", "--show-sdk-path"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try runXcrun(
            arguments: [
                "swiftc", "-typecheck", "-sdk", sdkPath,
                "-target", "arm64-apple-macos27.0", sourceURL.path,
            ]
        )
    }


    @Test
    func cleanExportVerifierBuildsTheStandalonePackage() async throws {
        let exportParent = temporaryDirectory()
        let cleanParent = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: exportParent)
            try? FileManager.default.removeItem(at: cleanParent)
        }
        try FileManager.default.createDirectory(at: exportParent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cleanParent, withIntermediateDirectories: true)
        let result = try await CoreAIIntegrationExporter().export(
            report: report(at: try fixtureURL()),
            contracts: [tensorContract(named: "main")],
            specializationConfiguration: .init(profile: .preferGPU),
            destinationParentURL: exportParent
        )
        let cleanPackageURL = cleanParent.appending(path: result.packageURL.lastPathComponent)
        try FileManager.default.copyItem(at: result.packageURL, to: cleanPackageURL)

        let output = try runExecutable(
            at: URL(filePath: "/usr/bin/python3"),
            arguments: [cleanPackageURL.appending(path: "verify-export.py").path],
            environment: [
                "DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer",
            ]
        )
        #expect(output.contains("Core AI integration export verified."))
        #expect(!FileManager.default.fileExists(atPath: cleanPackageURL.appending(path: ".build").path))

        let consumerURL = cleanParent.appending(path: "Consumer", directoryHint: .isDirectory)
        let consumerSourcesURL = consumerURL.appending(
            path: "Sources/Consumer",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: consumerSourcesURL,
            withIntermediateDirectories: true
        )
        let packageName = result.manifest.package.productName
        let dependencyPath = "../\(cleanPackageURL.lastPathComponent)"
        let consumerPackage = """
            // swift-tools-version: 6.4
            import PackageDescription

            let package = Package(
                name: "Consumer",
                platforms: [.macOS(.v27)],
                dependencies: [
                    .package(name: "GeneratedIntegration", path: "\(dependencyPath)"),
                ],
                targets: [
                    .executableTarget(
                        name: "Consumer",
                        dependencies: [
                            .product(
                                name: "\(packageName)",
                                package: "GeneratedIntegration"
                            ),
                        ]
                    ),
                ]
            )
            """ + "\n"
        try Data(consumerPackage.utf8).write(
            to: consumerURL.appending(path: "Package.swift"),
            options: .atomic
        )
        let consumerSource = """
            import \(packageName)
            import Foundation

            @main
            struct Consumer {
                static func main() throws {
                    print(try CoreAILabTensorFixtureCoreAIModelResources.modelURL().lastPathComponent)
                }
            }
            """ + "\n"
        try Data(consumerSource.utf8).write(
            to: consumerSourcesURL.appending(path: "main.swift"),
            options: .atomic
        )
        let consumerOutput = try runExecutable(
            at: URL(filePath: "/usr/bin/xcrun"),
            arguments: [
                "swift", "run",
                "--package-path", consumerURL.path,
                "--scratch-path", cleanParent.appending(path: "ConsumerScratch").path,
                "--disable-automatic-resolution",
            ],
            environment: [
                "DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer",
                "SWIFTPM_DISABLE_PACKAGE_REPOSITORY_CACHE": "1",
            ]
        )
        #expect(consumerOutput.contains("CoreAILabTensorFixture.aimodel"))

        let iOSConsumerURL = cleanParent.appending(
            path: "IOSConsumer",
            directoryHint: .isDirectory
        )
        let iOSConsumerSourcesURL = iOSConsumerURL.appending(
            path: "Sources/IOSConsumer",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: iOSConsumerSourcesURL,
            withIntermediateDirectories: true
        )
        let iOSConsumerPackage = """
            // swift-tools-version: 6.4
            import PackageDescription

            let package = Package(
                name: "IOSConsumer",
                platforms: [.iOS(.v27)],
                products: [
                    .library(name: "IOSConsumer", targets: ["IOSConsumer"]),
                ],
                dependencies: [
                    .package(name: "GeneratedIntegration", path: "\(dependencyPath)"),
                ],
                targets: [
                    .target(
                        name: "IOSConsumer",
                        dependencies: [
                            .product(
                                name: "\(packageName)",
                                package: "GeneratedIntegration"
                            ),
                        ]
                    ),
                ]
            )
            """ + "\n"
        try Data(iOSConsumerPackage.utf8).write(
            to: iOSConsumerURL.appending(path: "Package.swift"),
            options: .atomic
        )
        let iOSConsumerSource = """
            import \(packageName)

            public enum IOSConsumerIntegration {
                public static let assetRelativePath =
                    CoreAILabTensorFixtureCoreAIModelResources.assetRelativePath
            }
            """ + "\n"
        try Data(iOSConsumerSource.utf8).write(
            to: iOSConsumerSourcesURL.appending(path: "IOSConsumer.swift"),
            options: .atomic
        )
        let iOSBuildOutput = try runExecutable(
            at: URL(filePath: "/usr/bin/xcodebuild"),
            arguments: [
                "-scheme", "IOSConsumer",
                "-destination", "generic/platform=iOS",
                "-derivedDataPath", cleanParent.appending(path: "IOSDerivedData").path,
                "CODE_SIGNING_ALLOWED=NO",
                "build",
            ],
            environment: [
                "DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer",
                "SWIFTPM_DISABLE_PACKAGE_REPOSITORY_CACHE": "1",
            ],
            currentDirectoryURL: iOSConsumerURL
        )
        #expect(iOSBuildOutput.contains("BUILD SUCCEEDED"))
    }
    #endif

    private func report(at url: URL) -> CoreAIModelAssetReport {
        CoreAIModelAssetReport(
            url: url,
            isValid: true,
            author: "Core AI Lab",
            license: "MIT",
            description: "Fixture",
            functionNames: ["main"],
            computeTypes: ["Float32"]
        )
    }

    private func tensorContract(named name: String) -> CoreAIFunctionContract {
        CoreAIFunctionContract(
            name: name,
            inputs: [
                CoreAIFunctionValueContract(
                    name: "values",
                    kind: .tensor(
                        CoreAITensorContract(
                            scalarType: .float32,
                            shape: [1, 4],
                            hasDynamicShape: false,
                            minimumByteCount: 16
                        )
                    )
                ),
            ],
            states: [],
            outputs: [],
            unsupportedReason: nil
        )
    }

    private func imageContract(named name: String) -> CoreAIFunctionContract {
        CoreAIFunctionContract(
            name: name,
            inputs: [
                CoreAIFunctionValueContract(
                    name: "image",
                    kind: .image(CoreAIImageContract(width: 8, height: 8, pixelFormatType: 0))
                ),
            ],
            states: [],
            outputs: [],
            unsupportedReason: "Image input"
        )
    }

    private func statefulContract(named name: String) -> CoreAIFunctionContract {
        CoreAIFunctionContract(
            name: name,
            inputs: [],
            states: [
                CoreAIFunctionValueContract(
                    name: "cache",
                    kind: .tensor(
                        CoreAITensorContract(
                            scalarType: .float32,
                            shape: [1, 4],
                            hasDynamicShape: false,
                            minimumByteCount: 16
                        )
                    )
                ),
            ],
            outputs: [],
            unsupportedReason: nil
        )
    }

    private func descriptorlessContract(named name: String) -> CoreAIFunctionContract {
        CoreAIFunctionContract(
            name: name,
            inputs: [],
            states: [],
            outputs: [],
            unsupportedReason: "Core AI did not provide a descriptor for this function."
        )
    }

    private func fixtureURL() throws -> URL {
        try CoreAITestFixtures.tensorModelURL()
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private func packageSnapshot(at rootURL: URL) throws -> [String: Data] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        ) else {
            return [:]
        }
        var snapshot: [String: Data] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            #expect(values.isSymbolicLink != true)
            guard values.isRegularFile == true else { continue }
            let relativePath = String(url.path.dropFirst(rootURL.path.count + 1))
            snapshot[relativePath] = try Data(contentsOf: url)
        }
        return snapshot
    }

    #if os(macOS)
    private func checksumManifest(in packageURL: URL) throws -> CoreAIExportChecksumManifest {
        try JSONDecoder().decode(
            CoreAIExportChecksumManifest.self,
            from: Data(contentsOf: packageURL.appending(path: "coreai-checksums.json"))
        )
    }

    private func updateChecksum(
        for relativePath: String,
        data: Data,
        in packageURL: URL
    ) throws {
        let manifest = try checksumManifest(in: packageURL)
        let digest = Data(SHA256.hash(data: data))
        let files = manifest.files.map { file in
            if file.relativePath == relativePath {
                CoreAIExportChecksumManifest.File(
                    relativePath: relativePath,
                    sha256: hexadecimalString(digest),
                    byteCount: Int64(data.count)
                )
            } else {
                file
            }
        }
        let updated = CoreAIExportChecksumManifest(files: files)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(updated).write(
            to: packageURL.appending(path: "coreai-checksums.json"),
            options: .atomic
        )
    }

    private func hexadecimalString(_ data: Data) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(data.count * 2)
        for byte in data {
            bytes.append(digits[Int(byte >> 4)])
            bytes.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func runVerifierStructureOnly(
        in packageURL: URL
    ) throws -> (status: Int32, output: String) {
        try runExecutableAllowingFailure(
            at: URL(filePath: "/usr/bin/python3"),
            arguments: [
                packageURL.appending(path: "verify-export.py").path,
                "--structure-only",
            ]
        )
    }

    private func runXcrun(arguments: [String]) throws -> String {
        try runExecutable(at: URL(filePath: "/usr/bin/xcrun"), arguments: arguments)
    }

    private func runExecutable(
        at url: URL,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectoryURL: URL? = nil
    ) throws -> String {
        let outcome = try runExecutableAllowingFailure(
            at: url,
            arguments: arguments,
            environment: environment,
            currentDirectoryURL: currentDirectoryURL
        )
        guard outcome.status == 0 else {
            throw CocoaError(
                .executableRuntimeMismatch,
                userInfo: [NSDebugDescriptionErrorKey: outcome.output]
            )
        }
        return outcome.output
    }

    private func runExecutableAllowingFailure(
        at url: URL,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectoryURL: URL? = nil
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let outputURL = URL.temporaryDirectory.appending(path: UUID().uuidString)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        process.executableURL = url
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        try output.close()
        let data = try Data(contentsOf: outputURL)
        let text = String(decoding: data, as: UTF8.self)
        return (process.terminationStatus, text)
    }
    #endif
}
