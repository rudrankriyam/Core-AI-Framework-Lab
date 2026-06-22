import Foundation
import Testing
@testable import CoreAILab

struct CoreAIBenchmarkEvidenceTests {
    @Test
    func evidenceRoundTripsWithoutLosingTrialsOrTimings() throws {
        let document = CoreAIBenchmarkEvidenceDocument(
            report: try fixtureReport()
        )
        let codec = CoreAIBenchmarkEvidenceCodec()

        let decoded = try codec.decode(codec.encode(document))

        #expect(decoded == document)
        #expect(decoded.functionLoadTiming.attoseconds == 2_000_000_000_000_000)
        #expect(decoded.inputPreparationTiming.attoseconds == 3_000_000_000_000_000)
        #expect(decoded.warmupRuns.map(\.index) == [1])
        #expect(decoded.measuredRuns.map(\.index) == [1, 2])
        #expect(decoded.inputs.first?.seed == 42)
        #expect(decoded.artifact.sha256 == String(repeating: "a", count: 64))
        #expect(decoded.executionState.specializationCacheState == "cacheMiss")
        #expect(decoded.executionState.inferenceWarmupState == "warmedWithExcludedRuns")
        #expect(decoded.benchmarkEnvironment.startedThermalState == "nominal")
        #expect(decoded.benchmarkEnvironment.endedThermalState == "fair")
        #expect(decoded.benchmarkEnvironment.toolchain.xcodeBuild == "18A123")
    }

    @Test
    func evidenceEncodingIsDeterministicAndKeepsUnsupportedMetricsNullable() throws {
        let document = CoreAIBenchmarkEvidenceDocument(
            report: try fixtureReport()
        )
        let codec = CoreAIBenchmarkEvidenceCodec()

        let first = try codec.encode(document)
        let second = try codec.encode(document)
        let json = try #require(String(data: first, encoding: .utf8))

        #expect(first == second)
        #expect(json.contains("\"energyJoules\" : null"))
        #expect(json.contains("\"peakResidentMemoryBytes\" : null"))
        #expect(json.contains("\"memoryMeasurementStatus\" : \"notMeasured\""))
    }

    @Test
    func benchmarkEnvironmentDoesNotClaimToDescribeSpecializationTiming() throws {
        let data = try CoreAIBenchmarkEvidenceCodec().encode(
            CoreAIBenchmarkEvidenceDocument(report: try fixtureReport())
        )
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"benchmarkEnvironment\""))
        #expect(json.contains("\"functionLoadTiming\""))
        #expect(!json.contains("specializationTiming"))
        #expect(!json.contains("specializationDuration"))
    }

    @Test
    func codecValidatesBeforeEncoding() throws {
        let document = CoreAIBenchmarkEvidenceDocument(
            report: try fixtureReport(),
            schemaVersion: 99
        )

        #expect(throws: CoreAIBenchmarkEvidenceError.self) {
            try CoreAIBenchmarkEvidenceCodec().encode(document)
        }
    }

    @Test
    func evidenceRejectsMalformedArtifactDigests() throws {
        let report = try fixtureReport(
            artifactDigest: CoreAIArtifactDigest(
                sha256: "not-a-digest",
                kind: .modelAsset,
                byteCount: 13,
                fileCount: 2
            )
        )

        #expect(throws: CoreAIBenchmarkEvidenceError.self) {
            try CoreAIBenchmarkEvidenceDocument(report: report).validate()
        }
    }

    @Test
    func evidenceRejectsEveryFabricatedAggregate() throws {
        let codec = CoreAIBenchmarkEvidenceCodec()
        let data = try codec.encode(
            CoreAIBenchmarkEvidenceDocument(report: try fixtureReport())
        )
        let fabricatedTimings: [(String, Int64)] = [
            ("minimum", 10_100_000_000_000_000),
            ("median", 10_500_000_000_000_000),
            ("mean", 10_500_000_000_000_000),
            ("maximum", 11_900_000_000_000_000),
            ("standardDeviation", 500_000_000_000_000)
        ]

        for (key, attoseconds) in fabricatedTimings {
            let fabricated = try mutateStatistics(in: data) { statistics in
                var timing = try #require(
                    statistics[key] as? [String: Any]
                )
                timing["attoseconds"] = attoseconds
                statistics[key] = timing
            }
            #expect(throws: CoreAIBenchmarkEvidenceError.self) {
                try codec.decode(fabricated)
            }
        }

        let fabricatedThroughput = try mutateStatistics(in: data) {
            $0["runsPerSecond"] = 91.0
        }
        #expect(throws: CoreAIBenchmarkEvidenceError.self) {
            try codec.decode(fabricatedThroughput)
        }

        let p95Data = try codec.encode(
            CoreAIBenchmarkEvidenceDocument(
                report: try fixtureReport(measuredMilliseconds: Array(1...20))
            )
        )
        let fabricatedP95 = try mutateStatistics(in: p95Data) { statistics in
            var timing = try #require(
                statistics["p95"] as? [String: Any]
            )
            timing["attoseconds"] = 18_500_000_000_000_000
            statistics["p95"] = timing
        }
        #expect(throws: CoreAIBenchmarkEvidenceError.self) {
            try codec.decode(fabricatedP95)
        }
    }

    @Test
    func exportedEvidenceNeverContainsTheSourcePath() throws {
        let report = try fixtureReport(
            assetName: "/Users/alice/Private Models/secret.aimodel"
        )

        let data = try CoreAIBenchmarkEvidenceCodec().encode(
            CoreAIBenchmarkEvidenceDocument(report: report)
        )
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("/Users/alice"))
        #expect(!json.contains("Private Models"))
        #expect(!json.contains("file://"))
    }

    @Test
    func artifactDigestDoesNotDependOnItsLocalRootPath() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "CoreAIBenchmarkEvidenceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appending(path: "first.aimodel", directoryHint: .isDirectory)
        let second = root.appending(path: "second.aimodel", directoryHint: .isDirectory)
        try makeArtifact(at: first)
        try makeArtifact(at: second)
        let digester = CoreAIArtifactStore(
            rootURL: root.appending(path: "unused-store")
        )

        let firstDigest = try await digester.digest(at: first)
        let secondDigest = try await digester.digest(at: second)

        #expect(firstDigest == secondDigest)
        #expect(firstDigest.sha256.count == 64)
        #expect(firstDigest.fileCount == 2)
    }

    private func fixtureReport(
        assetName: String = "fixture.aimodel",
        artifactDigest: CoreAIArtifactDigest = CoreAIArtifactDigest(
            sha256: String(repeating: "a", count: 64),
            kind: .modelAsset,
            byteCount: 13,
            fileCount: 2
        ),
        measuredMilliseconds: [Int] = [10, 12]
    ) throws -> CoreAIFunctionBenchmarkReport {
        let trials = measuredMilliseconds.enumerated().map { index, milliseconds in
            CoreAIBenchmarkTrial(
                index: index + 1,
                duration: .milliseconds(milliseconds)
            )
        }
        return CoreAIFunctionBenchmarkReport(
            id: try #require(
                UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")
            ),
            assetName: assetName,
            artifactDigest: artifactDigest,
            specializationConfiguration: CoreAISpecializationConfiguration(
                profile: .automatic,
                expectFrequentReshapes: false
            ),
            specializationDuration: .milliseconds(25),
            loadedFromCache: false,
            benchmarkConfiguration: CoreAIFunctionBenchmarkConfiguration(
                warmupRuns: 1,
                measuredRuns: measuredMilliseconds.count
            ),
            inputPlans: [
                CoreAIFunctionInputPlan(
                    name: "values",
                    shape: [1, 4],
                    generator: .random,
                    seed: 42
                )
            ],
            result: CoreAIFunctionBenchmarkResult(
                functionName: "scale_and_bias",
                functionLoadDuration: .milliseconds(2),
                inputPreparationDuration: .milliseconds(3),
                warmupDurations: [.milliseconds(5)],
                trials: trials,
                stoppedEarly: false,
                statistics: try CoreAIBenchmarkStatistics(trials: trials),
                outputs: [
                    CoreAIFunctionOutputSummary(
                        name: "result",
                        typeDescription: "Float32",
                        shape: [1, 4],
                        strides: [4, 1],
                        elementCount: 4,
                        sampledElementCount: 4,
                        minimum: 0,
                        maximum: 1,
                        mean: 0.5,
                        nonFiniteCount: 0,
                        preview: ["0", "1"]
                    )
                ],
                environment: CoreAIBenchmarkEnvironment(
                    capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
                    platform: "macOS",
                    operatingSystem: "Version 27.0 (Build 26A123)",
                    deviceArchitectureName: "h17g",
                    availableComputeUnits: ["GPU", "CPU"],
                    processorCount: 12,
                    physicalMemoryBytes: 32_000_000_000,
                    buildConfiguration: .release,
                    startedThermalState: .nominal,
                    endedThermalState: .fair,
                    toolchain: CoreAIBenchmarkToolchain(
                        xcodeVersionCode: "2700",
                        xcodeBuild: "18A123",
                        sdkName: "macosx27.0",
                        sdkBuild: "26A123",
                        compilerIdentifier: "com.apple.compilers.llvm.clang.1_0",
                        swiftCompilerVersionConstraint: ">=6.4",
                        swiftLanguageMode: "6"
                    )
                )
            )
        )
    }

    private func makeArtifact(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        try Data("model-bytes".utf8).write(
            to: url.appending(path: "main.mlirb")
        )
        try Data("{}".utf8).write(
            to: url.appending(path: "metadata.json")
        )
    }

    private func mutateStatistics(
        in data: Data,
        _ mutation: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        var root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var statistics = try #require(root["statistics"] as? [String: Any])
        try mutation(&statistics)
        root["statistics"] = statistics
        return try JSONSerialization.data(withJSONObject: root)
    }
}
