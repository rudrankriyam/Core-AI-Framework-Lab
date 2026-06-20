#if os(macOS)
import Foundation

actor CoreAIConversionEnvironmentDoctor {
    func inspect(
        uvExecutableURL: URL?,
        repositoryURL: URL?,
        outputDirectoryURL: URL,
        expectedRepositoryRevision: String
    ) async -> CoreAIConversionEnvironmentReport {
        let repositoryAccess = repositoryURL?.startAccessingSecurityScopedResource() ?? false
        let outputAccess = outputDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if repositoryAccess {
                repositoryURL?.stopAccessingSecurityScopedResource()
            }
            if outputAccess {
                outputDirectoryURL.stopAccessingSecurityScopedResource()
            }
        }

        var checks: [CoreAIConversionEnvironmentCheck] = []
        checks.append(await checkUV(uvExecutableURL))
        checks.append(checkRepository(repositoryURL))
        checks.append(
            await checkRepositoryRevision(
                repositoryURL,
                expected: expectedRepositoryRevision
            )
        )
        checks.append(await checkRepositoryCleanliness(repositoryURL))
        checks.append(checkOutputDirectory(outputDirectoryURL))
        checks.append(checkDiskCapacity(outputDirectoryURL))
        checks.append(await checkXcode())
        checks.append(checkArchitecture())
        return CoreAIConversionEnvironmentReport(checks: checks)
    }

    private func checkUV(_ executableURL: URL?) async -> CoreAIConversionEnvironmentCheck {
        guard let executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return CoreAIConversionEnvironmentCheck(
                id: "uv",
                title: "uv",
                detail: "Install uv or choose its executable before converting.",
                status: .failed
            )
        }

        do {
            let result = try await capture(
                executableURL: executableURL,
                arguments: ["--version"],
                workingDirectoryURL: nil
            )
            return CoreAIConversionEnvironmentCheck(
                id: "uv",
                title: "uv",
                detail: result.output.isEmpty ? executableURL.path : result.output,
                status: result.status == 0 ? .passed : .failed
            )
        } catch {
            return CoreAIConversionEnvironmentCheck(
                id: "uv",
                title: "uv",
                detail: error.localizedDescription,
                status: .failed
            )
        }
    }

    private func checkRepository(_ repositoryURL: URL?) -> CoreAIConversionEnvironmentCheck {
        guard let repositoryURL else {
            return CoreAIConversionEnvironmentCheck(
                id: "repository",
                title: "Apple recipe repository",
                detail: "Choose a local clone of apple/coreai-models.",
                status: .failed
            )
        }

        guard CoreAIConversionEnvironmentDetector.isCoreAIModelsRepository(repositoryURL) else {
            return CoreAIConversionEnvironmentCheck(
                id: "repository",
                title: "Apple recipe repository",
                detail: "The selected folder is missing pyproject.toml, python, or models.",
                status: .failed
            )
        }

        let isWritable = FileManager.default.isWritableFile(atPath: repositoryURL.path)
        return CoreAIConversionEnvironmentCheck(
            id: "repository",
            title: "Apple recipe repository",
            detail: isWritable
                ? repositoryURL.path
                : "The repository is read-only. uv needs to create or update its environment.",
            status: isWritable ? .passed : .failed
        )
    }

    private func checkRepositoryRevision(
        _ repositoryURL: URL?,
        expected: String
    ) async -> CoreAIConversionEnvironmentCheck {
        guard let repositoryURL,
              CoreAIConversionEnvironmentDetector.isCoreAIModelsRepository(repositoryURL) else {
            return CoreAIConversionEnvironmentCheck(
                id: "revision",
                title: "Recipe revision",
                detail: "Revision will be checked after a repository is selected.",
                status: .warning
            )
        }

        do {
            let result = try await capture(
                executableURL: URL(filePath: "/usr/bin/git"),
                arguments: ["rev-parse", "HEAD"],
                workingDirectoryURL: repositoryURL
            )
            guard result.status == 0, !result.output.isEmpty else {
                return CoreAIConversionEnvironmentCheck(
                    id: "revision",
                    title: "Recipe revision",
                    detail: "Git could not resolve the selected repository revision.",
                    status: .failed
                )
            }

            let matches = result.output == expected
            return CoreAIConversionEnvironmentCheck(
                id: "revision",
                title: "Recipe revision",
                detail: matches
                    ? "Pinned at \(expected.prefix(12))."
                    : "Selected \(result.output.prefix(12)); catalog expects \(expected.prefix(12)).",
                status: matches ? .passed : .failed
            )
        } catch {
            return CoreAIConversionEnvironmentCheck(
                id: "revision",
                title: "Recipe revision",
                detail: error.localizedDescription,
                status: .failed
            )
        }
    }

    private func checkRepositoryCleanliness(
        _ repositoryURL: URL?
    ) async -> CoreAIConversionEnvironmentCheck {
        guard let repositoryURL,
              CoreAIConversionEnvironmentDetector.isCoreAIModelsRepository(repositoryURL) else {
            return CoreAIConversionEnvironmentCheck(
                id: "worktree",
                title: "Recipe worktree",
                detail: "Worktree changes will be checked after a repository is selected.",
                status: .warning
            )
        }

        do {
            let result = try await capture(
                executableURL: URL(filePath: "/usr/bin/git"),
                arguments: ["status", "--porcelain", "--untracked-files=normal"],
                workingDirectoryURL: repositoryURL
            )
            guard result.status == 0 else {
                return CoreAIConversionEnvironmentCheck(
                    id: "worktree",
                    title: "Recipe worktree",
                    detail: "Git could not inspect the selected recipe worktree.",
                    status: .failed
                )
            }

            let isClean = result.output.isEmpty
            return CoreAIConversionEnvironmentCheck(
                id: "worktree",
                title: "Recipe worktree",
                detail: isClean
                    ? "No local recipe changes detected."
                    : "Commit, stash, or remove local changes before conversion.",
                status: isClean ? .passed : .failed
            )
        } catch {
            return CoreAIConversionEnvironmentCheck(
                id: "worktree",
                title: "Recipe worktree",
                detail: error.localizedDescription,
                status: .failed
            )
        }
    }

    private func checkOutputDirectory(_ outputURL: URL) -> CoreAIConversionEnvironmentCheck {
        let fileManager = FileManager.default
        let writableURL = fileManager.fileExists(atPath: outputURL.path)
            ? outputURL
            : outputURL.deletingLastPathComponent()
        let isWritable = fileManager.isWritableFile(atPath: writableURL.path)

        return CoreAIConversionEnvironmentCheck(
            id: "output",
            title: "Output folder",
            detail: isWritable
                ? outputURL.path
                : "Core AI Lab cannot write to \(writableURL.path).",
            status: isWritable ? .passed : .failed
        )
    }

    private func checkDiskCapacity(_ outputURL: URL) -> CoreAIConversionEnvironmentCheck {
        let probeURL = FileManager.default.fileExists(atPath: outputURL.path)
            ? outputURL
            : outputURL.deletingLastPathComponent()
        let values = try? probeURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let availableBytes = values?.volumeAvailableCapacityForImportantUsage else {
            return CoreAIConversionEnvironmentCheck(
                id: "disk",
                title: "Available storage",
                detail: "Storage capacity could not be read.",
                status: .warning
            )
        }

        let available = Int64(availableBytes)
        let recommended: Int64 = 10 * 1_024 * 1_024 * 1_024
        return CoreAIConversionEnvironmentCheck(
            id: "disk",
            title: "Available storage",
            detail: ByteCountFormatStyle(style: .file).format(available),
            status: available >= recommended ? .passed : .warning
        )
    }

    private func checkXcode() async -> CoreAIConversionEnvironmentCheck {
        do {
            let result = try await capture(
                executableURL: URL(filePath: "/usr/bin/xcrun"),
                arguments: ["--find", "coreai-build"],
                workingDirectoryURL: nil
            )
            return CoreAIConversionEnvironmentCheck(
                id: "xcode",
                title: "Core AI toolchain",
                detail: result.status == 0 && !result.output.isEmpty
                    ? result.output
                    : "The selected Xcode toolchain does not expose coreai-build.",
                status: result.status == 0 ? .passed : .failed
            )
        } catch {
            return CoreAIConversionEnvironmentCheck(
                id: "xcode",
                title: "Core AI toolchain",
                detail: error.localizedDescription,
                status: .failed
            )
        }
    }

    private func checkArchitecture() -> CoreAIConversionEnvironmentCheck {
        #if arch(arm64)
        CoreAIConversionEnvironmentCheck(
            id: "architecture",
            title: "Apple silicon",
            detail: "Running natively on arm64.",
            status: .passed
        )
        #else
        CoreAIConversionEnvironmentCheck(
            id: "architecture",
            title: "Apple silicon",
            detail: "Core AI conversion requires an Apple silicon Mac.",
            status: .failed
        )
        #endif
    }

    private func capture(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL?
    ) async throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        let (terminationStream, terminationContinuation) = AsyncStream.makeStream(of: Int32.self)

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectoryURL
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { terminatedProcess in
            terminationContinuation.yield(terminatedProcess.terminationStatus)
            terminationContinuation.finish()
        }

        try process.run()

        var data = Data()
        for try await byte in pipe.fileHandleForReading.bytes {
            data.append(byte)
        }
        let status = await terminationStream.first(where: { _ in true }) ?? -1
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (status, output)
    }
}
#endif
