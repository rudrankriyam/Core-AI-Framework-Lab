import CoreAI
import Foundation
import Testing
@testable import CoreAILab

struct CoreAIIntegrationExportTests {
    @Test
    func manifestRoundTripsWithoutSourcePathOrBookmarkData() throws {
        let manifest = CoreAIExportManifest(
            artifact: .init(
                relativePath: "Resources/fixture.aimodel",
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
        #expect(manifest.schemaVersion == 1)
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
        let output = generator.generate(
            assetName: "demo.aimodel",
            contracts: [unsupported, supported]
        )

        #expect(output.source.contains("public actor DemoCoreAIModel"))
        #expect(output.source.contains("public enum DemoCoreAIModelError"))
        #expect(!output.source.contains("GeneratedCoreAIError"))
        #expect(output.source.contains("func decodeToken"))
        #expect(output.source.contains("loadFunction(named: \"decode-token\")"))
        #expect(!output.source.contains("func runClass"))
        #expect(unsupported.generatedRuntimeUnsupportedReason?.contains("image") == true)
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
        let firstSource = try Data(
            contentsOf: first.packageURL.appending(path: "Sources/CoreAILabTensorFixtureCoreAIModel.swift")
        )
        let secondSource = try Data(
            contentsOf: second.packageURL.appending(path: "Sources/CoreAILabTensorFixtureCoreAIModel.swift")
        )
        #expect(firstSource == secondSource)
        let compileScript = try String(
            contentsOf: first.packageURL.appending(path: "compile-model.sh"),
            encoding: .utf8
        )
        #expect(compileScript.contains("--platform iOS"))
        #expect(compileScript.contains("--platform macOS"))
        #expect(compileScript.contains("--min-deployment-version 27.0"))
        #expect(!compileScript.contains("--preferred-compute"))

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

    private func fixtureURL() throws -> URL {
        try CoreAITestFixtures.tensorModelURL()
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    #if os(macOS)
    private func runXcrun(arguments: [String]) throws -> String {
        try runExecutable(at: URL(filePath: "/usr/bin/xcrun"), arguments: arguments)
    }

    private func runExecutable(at url: URL, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = url
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw CocoaError(.executableRuntimeMismatch, userInfo: [NSDebugDescriptionErrorKey: text])
        }
        return text
    }
    #endif
}
