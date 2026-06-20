#if os(macOS)
import Foundation

actor CoreAIConversionProcessRunner {
    private var currentProcess: Process?
    private var hasActiveRun = false

    func run(
        request: CoreAIConversionRequest,
        onEvent: @Sendable (CoreAIConversionProcessEvent) async -> Void
    ) async throws -> CoreAIConversionProcessResult {
        guard !hasActiveRun else {
            throw CoreAIConversionError.alreadyRunning
        }
        hasActiveRun = true
        defer { hasActiveRun = false }

        return try await withTaskCancellationHandler {
            try await execute(request: request, onEvent: onEvent)
        } onCancel: {
            Task {
                await self.cancel()
            }
        }
    }

    func cancel() async {
        guard let currentProcess else { return }
        await stop(currentProcess)
    }

    private func execute(
        request: CoreAIConversionRequest,
        onEvent: @Sendable (CoreAIConversionProcessEvent) async -> Void
    ) async throws -> CoreAIConversionProcessResult {
        let repositoryAccess = request.command.workingDirectoryURL
            .startAccessingSecurityScopedResource()
        let outputAccess = request.outputDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if repositoryAccess {
                request.command.workingDirectoryURL.stopAccessingSecurityScopedResource()
            }
            if outputAccess {
                request.outputDirectoryURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: request.outputDirectoryURL,
            withIntermediateDirectories: true
        )
        let artifactBaseline = CoreAIConversionArtifactDiscoverer.snapshot(
            in: request.outputDirectoryURL
        )

        let logURL = request.outputDirectoryURL.appending(
            path: "coreai-lab-\(slug(request.modelName))-\(UUID().uuidString.lowercased()).log"
        )
        try Data().write(to: logURL, options: .atomic)
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer {
            try? logHandle.close()
        }

        try write(evidenceHeader(for: request), to: logHandle)

        let process = Process()
        let pipe = Pipe()
        let (terminationStream, terminationContinuation) = AsyncStream.makeStream(of: Int32.self)

        process.executableURL = request.command.executableURL
        process.arguments = request.command.arguments
        process.currentDirectoryURL = request.command.workingDirectoryURL
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        process.environment = childEnvironment(for: request.command.executableURL)
        process.terminationHandler = { terminatedProcess in
            terminationContinuation.yield(terminatedProcess.terminationStatus)
            terminationContinuation.finish()
        }

        currentProcess = process
        defer {
            currentProcess = nil
        }

        try Task.checkCancellation()
        await onEvent(.logCreated(logURL))
        try Task.checkCancellation()

        let clock = ContinuousClock()
        let start = clock.now
        do {
            try process.run()
            await onEvent(.started(processIdentifier: process.processIdentifier))

            for try await line in pipe.fileHandleForReading.bytes.lines {
                try Task.checkCancellation()
                try write("\(line)\n", to: logHandle)
                await onEvent(.output(line))
            }

            let exitCode = await terminationStream.first(where: { _ in true }) ?? -1
            let duration = start.duration(to: clock.now)
            try Task.checkCancellation()
            guard exitCode == 0 else {
                throw CoreAIConversionError.processFailed(exitCode)
            }

            return CoreAIConversionProcessResult(
                exitCode: exitCode,
                duration: duration,
                artifacts: CoreAIConversionArtifactDiscoverer.discoverChanges(
                    in: request.outputDirectoryURL,
                    comparedTo: artifactBaseline
                ),
                logURL: logURL
            )
        } catch {
            await stop(process)
            throw error
        }
    }

    private func stop(_ process: Process) async {
        guard process.isRunning else { return }
        process.interrupt()
        try? await Task.sleep(for: .seconds(1))
        if process.isRunning {
            process.terminate()
        }
        if process.isRunning {
            process.waitUntilExit()
        }
    }

    private func childEnvironment(for executableURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let executableDirectory = executableURL.deletingLastPathComponent().path
        environment["PATH"] = "\(executableDirectory):/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
        environment["PYTHONUNBUFFERED"] = "1"
        environment["NO_COLOR"] = "1"
        return environment
    }

    private func write(_ string: String, to handle: FileHandle) throws {
        try handle.write(contentsOf: Data(string.utf8))
    }

    private func evidenceHeader(for request: CoreAIConversionRequest) -> String {
        var lines = [
            "Core AI Lab conversion evidence",
            "Created: \(Date.now.formatted(.iso8601))",
            "Working directory: \(request.command.workingDirectoryURL.path)",
            "Output directory: \(request.outputDirectoryURL.path)",
        ]

        if !request.environmentChecks.isEmpty {
            lines.append("Environment:")
            lines.append(contentsOf: request.environmentChecks.map { check in
                "  [\(evidenceStatus(check.status))] \(check.title): \(check.detail)"
            })
        }

        lines.append("Command: \(request.command.displayString)")
        return lines.joined(separator: "\n") + "\n\n"
    }

    private func evidenceStatus(
        _ status: CoreAIConversionEnvironmentCheck.Status
    ) -> String {
        switch status {
        case .passed:
            "passed"
        case .warning:
            "warning"
        case .failed:
            "failed"
        }
    }

    private func slug(_ value: String) -> String {
        value.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { partialResult, character in
                if character != "-" || partialResult.last != "-" {
                    partialResult.append(character)
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
#endif
