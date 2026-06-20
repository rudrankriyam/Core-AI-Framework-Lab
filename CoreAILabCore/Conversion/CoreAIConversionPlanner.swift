import Foundation

enum CoreAIConversionPlanner {
    static func exportCommand(
        model: AppleCoreAIModel,
        uvExecutableURL: URL,
        repositoryURL: URL,
        outputDirectoryURL: URL,
        precision: CoreAIConversionPrecision?,
        overwrite: Bool
    ) -> CoreAIConversionCommand {
        var arguments = model.exportProgramArguments

        if model.exportScript != nil, let precision {
            arguments.append(contentsOf: ["--dtype", precision.rawValue])
        }

        arguments.append(contentsOf: ["--output-dir", outputDirectoryURL.path])
        if overwrite {
            arguments.append("--overwrite")
        }

        return CoreAIConversionCommand(
            executableURL: uvExecutableURL,
            arguments: arguments,
            workingDirectoryURL: repositoryURL
        )
    }

    static func validationCommand(
        model: AppleCoreAIModel,
        uvExecutableURL: URL,
        repositoryURL: URL
    ) -> CoreAIConversionCommand {
        var arguments = [
            "run",
            "coreai.model.registry",
            "--model-info",
            model.shortName,
            "--type",
            model.registryType,
        ]

        if model.type == "llm", let variant = model.variant {
            arguments.append(contentsOf: ["--platform", variant])
        }
        arguments.append("--as-export-args")

        return CoreAIConversionCommand(
            executableURL: uvExecutableURL,
            arguments: arguments,
            workingDirectoryURL: repositoryURL
        )
    }
}
