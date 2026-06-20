#if os(macOS)
import Foundation

enum CoreAIConversionEnvironmentDetector {
    static func findUVExecutable() -> URL? {
        executableCandidates(named: "uv").first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    static func findRepository() -> URL? {
        repositoryCandidates.first(where: isCoreAIModelsRepository)
    }

    static var defaultOutputDirectory: URL {
        if let configuredPath = ProcessInfo.processInfo.environment["COREAI_LAB_OUTPUT_DIRECTORY"] {
            return URL(filePath: configuredPath, directoryHint: .isDirectory)
        }

        return URL.downloadsDirectory.appending(
            path: "Core AI Lab Exports",
            directoryHint: .isDirectory
        )
    }

    static func isCoreAIModelsRepository(_ url: URL) -> Bool {
        let requiredPaths = ["pyproject.toml", "python", "models"]
        return requiredPaths.allSatisfy {
            FileManager.default.fileExists(atPath: url.appending(path: $0).path)
        }
    }

    private static func executableCandidates(named name: String) -> [URL] {
        let pathCandidates = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map { URL(filePath: String($0), directoryHint: .isDirectory) }
            .map { $0.appending(path: name) } ?? []

        return pathCandidates + [
            URL(filePath: "/opt/homebrew/bin/\(name)"),
            URL(filePath: "/usr/local/bin/\(name)"),
            URL.homeDirectory.appending(path: ".local/bin/\(name)"),
            URL.homeDirectory.appending(path: ".cargo/bin/\(name)"),
        ]
    }

    private static var repositoryCandidates: [URL] {
        var candidates: [URL] = []
        if let configuredPath = ProcessInfo.processInfo.environment["COREAI_MODELS_REPOSITORY"] {
            candidates.append(URL(filePath: configuredPath, directoryHint: .isDirectory))
        }

        candidates.append(contentsOf: [
            URL.homeDirectory.appending(path: "Developer/coreai-models", directoryHint: .isDirectory),
            URL.homeDirectory.appending(path: "Developer/Apple/coreai-models", directoryHint: .isDirectory),
            URL.homeDirectory.appending(path: "Developer/Models/coreai-models", directoryHint: .isDirectory),
        ])
        return candidates
    }
}
#endif
