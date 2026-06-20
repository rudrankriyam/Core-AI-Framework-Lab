#if os(macOS)
import Foundation
import Testing
@testable import CoreAILab

struct CoreAIConversionProcessRunnerTests {
    @Test
    func runnerStreamsACommandAndPersistsEvidence() async throws {
        let outputURL = URL.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let runner = CoreAIConversionProcessRunner()
        let result = try await runner.run(
            request: CoreAIConversionRequest(
                modelName: "fixture",
                command: CoreAIConversionCommand(
                    executableURL: URL(filePath: "/bin/echo"),
                    arguments: ["converted fixture"],
                    workingDirectoryURL: URL(filePath: "/tmp", directoryHint: .isDirectory)
                ),
                outputDirectoryURL: outputURL
            )
        ) { _ in }

        #expect(result.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: result.logURL.path))
        let log = try String(contentsOf: result.logURL, encoding: .utf8)
        #expect(log.contains("converted fixture"))
    }

    @Test
    func discovererFindsNestedModelPackages() throws {
        let outputURL = URL.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let nestedURL = outputURL.appending(path: "bundle", directoryHint: .isDirectory)
        let modelURL = nestedURL.appending(path: "encoder.aimodel", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        try FileManager.default.createDirectory(
            at: modelURL,
            withIntermediateDirectories: true
        )
        let artifacts = CoreAIConversionArtifactDiscoverer.discover(in: outputURL)

        let discoveredURLs = artifacts.map(\.url).map { $0.resolvingSymlinksInPath() }
        #expect(discoveredURLs == [modelURL.resolvingSymlinksInPath()])
    }

    @Test
    func runnerReportsOnlyArtifactsChangedByTheCurrentRun() async throws {
        let outputURL = URL.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let existingURL = outputURL.appending(path: "existing.aimodel", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.createDirectory(
            at: existingURL,
            withIntermediateDirectories: true
        )

        let runner = CoreAIConversionProcessRunner()
        let result = try await runner.run(
            request: CoreAIConversionRequest(
                modelName: "fixture",
                command: CoreAIConversionCommand(
                    executableURL: URL(filePath: "/bin/mkdir"),
                    arguments: ["created.aimodel"],
                    workingDirectoryURL: outputURL
                ),
                outputDirectoryURL: outputURL
            )
        ) { _ in }

        #expect(result.artifacts.map(\.name) == ["created.aimodel"])
    }

    @Test
    func cancellationBeforeLaunchDoesNotExecuteTheCommand() async throws {
        let outputURL = URL.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let markerURL = outputURL.appending(path: "command-ran")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let runner = CoreAIConversionProcessRunner()
        let (eventStream, eventContinuation) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            try await runner.run(
                request: CoreAIConversionRequest(
                    modelName: "fixture",
                    command: CoreAIConversionCommand(
                        executableURL: URL(filePath: "/usr/bin/touch"),
                        arguments: [markerURL.path],
                        workingDirectoryURL: URL(filePath: "/tmp", directoryHint: .isDirectory)
                    ),
                    outputDirectoryURL: outputURL
                )
            ) { event in
                if case .logCreated = event {
                    eventContinuation.yield()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }

        _ = await eventStream.first(where: { _ in true })
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation before process launch.")
        } catch is CancellationError {
            // Expected.
        }
        eventContinuation.finish()

        #expect(!FileManager.default.fileExists(atPath: markerURL.path))
    }

    @Test
    func runnerRejectsAConcurrentRunBeforeProcessLaunch() async throws {
        let outputURL = URL.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let runner = CoreAIConversionProcessRunner()
        let (eventStream, eventContinuation) = AsyncStream.makeStream(of: Void.self)
        let firstTask = Task {
            try await runner.run(
                request: CoreAIConversionRequest(
                    modelName: "first",
                    command: CoreAIConversionCommand(
                        executableURL: URL(filePath: "/bin/echo"),
                        arguments: ["first"],
                        workingDirectoryURL: URL(filePath: "/tmp", directoryHint: .isDirectory)
                    ),
                    outputDirectoryURL: outputURL
                )
            ) { event in
                if case .logCreated = event {
                    eventContinuation.yield()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }

        _ = await eventStream.first(where: { _ in true })
        do {
            _ = try await runner.run(
                request: CoreAIConversionRequest(
                    modelName: "second",
                    command: CoreAIConversionCommand(
                        executableURL: URL(filePath: "/bin/echo"),
                        arguments: ["second"],
                        workingDirectoryURL: URL(filePath: "/tmp", directoryHint: .isDirectory)
                    ),
                    outputDirectoryURL: outputURL
                )
            ) { _ in }
            Issue.record("Expected the runner to reject a concurrent conversion.")
        } catch CoreAIConversionError.alreadyRunning {
            // Expected.
        } catch {
            Issue.record("Unexpected concurrent-run error: \(error)")
        }

        firstTask.cancel()
        _ = try? await firstTask.value
        eventContinuation.finish()
    }
}
#endif
