import Foundation

struct CoreAIAheadOfTimeCompileScriptGenerator: Sendable {
    func generate(
        assetRelativePath: String,
        configuration: CoreAISpecializationConfiguration
    ) -> String {
        var argumentLines = [
            "  --output \"$SCRIPT_DIR/Compiled\"",
            "  --platform iOS",
            "  --platform macOS",
            "  --min-deployment-version 27.0",
        ]
        switch configuration.profile {
        case .preferGPU:
            argumentLines.append("  --preferred-compute gpu")
        case .preferNeuralEngine:
            argumentLines.append("  --preferred-compute neural-engine")
        case .automatic, .cpuOnly:
            break
        }
        if configuration.expectFrequentReshapes {
            argumentLines.append("  --expect-frequent-reshapes")
        }
        let continuation = argumentLines.joined(separator: " \\\n")
        let cpuNote = configuration.profile == .cpuOnly
            ? "# coreai-build has no CPU-only compile flag. Pass .cpuOnly to the generated runtime loader.\n"
            : ""
        return """
            #!/bin/sh
            set -eu

            SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
            ASSET_RELATIVE_PATH=\(shellLiteral(assetRelativePath))

            \(cpuNote)mkdir -p "$SCRIPT_DIR/Compiled"
            xcrun coreai-build compile "$SCRIPT_DIR/$ASSET_RELATIVE_PATH" \\
            \(continuation)
            """ + "\n"
    }

    private func shellLiteral(_ value: String) -> String {
        "'" + value.replacing("'", with: "'\"'\"'") + "'"
    }
}
