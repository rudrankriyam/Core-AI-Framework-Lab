import Foundation
import Testing
@testable import CoreAILab

struct CoreAIConversionPlannerTests {
    @Test
    func terminalPhasesAllowAnotherConversion() {
        #expect(CoreAIConversionPhase.ready.allowsStartingConversion)
        #expect(CoreAIConversionPhase.succeeded.allowsStartingConversion)
        #expect(CoreAIConversionPhase.failed.allowsStartingConversion)
        #expect(CoreAIConversionPhase.canceled.allowsStartingConversion)

        #expect(!CoreAIConversionPhase.checking.allowsStartingConversion)
        #expect(!CoreAIConversionPhase.running.allowsStartingConversion)
        #expect(!CoreAIConversionPhase.canceling.allowsStartingConversion)
    }

    @Test
    func yolosPlanUsesTypedArgumentsAndRecommendedPrecision() throws {
        let model = try #require(
            try loadCatalog().models.first { $0.shortName == "yolos-tiny" }
        )
        let command = CoreAIConversionPlanner.exportCommand(
            model: model,
            uvExecutableURL: URL(filePath: "/opt/homebrew/bin/uv"),
            repositoryURL: URL(filePath: "/tmp/coreai-models", directoryHint: .isDirectory),
            outputDirectoryURL: URL(filePath: "/tmp/Core AI Exports", directoryHint: .isDirectory),
            precision: .float16,
            overwrite: true
        )

        #expect(
            command.arguments == [
                "run",
                "models/yolo/export.py",
                "--model",
                "hustvl/yolos-tiny",
                "--dtype",
                "float16",
                "--output-dir",
                "/tmp/Core AI Exports",
                "--overwrite",
            ]
        )
        #expect(
            command.displayString
                == "/opt/homebrew/bin/uv run models/yolo/export.py --model hustvl/yolos-tiny --dtype float16 --output-dir '/tmp/Core AI Exports' --overwrite"
        )
    }

    @Test
    func languagePlanPreservesRegistryDefaults() throws {
        let model = try #require(
            try loadCatalog().models.first {
                $0.shortName == "qwen3-0.6b" && $0.variant == "macOS"
            }
        )
        let command = CoreAIConversionPlanner.exportCommand(
            model: model,
            uvExecutableURL: URL(filePath: "/usr/local/bin/uv"),
            repositoryURL: URL(filePath: "/tmp/coreai-models", directoryHint: .isDirectory),
            outputDirectoryURL: URL(filePath: "/tmp/exports", directoryHint: .isDirectory),
            precision: .float32,
            overwrite: false
        )

        #expect(
            command.arguments == [
                "run",
                "coreai.llm.export",
                "Qwen/Qwen3-0.6B",
                "--compression",
                "4bit",
                "--compute-precision",
                "float16",
                "--max-context-length",
                "8192",
                "--output-dir",
                "/tmp/exports",
            ]
        )
    }

    @Test
    func validationPlanUsesPinnedRegistryLookup() throws {
        let model = try #require(
            try loadCatalog().models.first {
                $0.shortName == "qwen3-0.6b" && $0.variant == "iOS"
            }
        )
        let command = CoreAIConversionPlanner.validationCommand(
            model: model,
            uvExecutableURL: URL(filePath: "/opt/homebrew/bin/uv"),
            repositoryURL: URL(filePath: "/tmp/coreai-models", directoryHint: .isDirectory)
        )

        #expect(
            command.arguments == [
                "run",
                "coreai.model.registry",
                "--model-info",
                "qwen3-0.6b",
                "--type",
                "llm",
                "--platform",
                "iOS",
                "--as-export-args",
            ]
        )
    }

    @Test
    func everyCatalogRecipeBuildsAnExplicitExportCommand() throws {
        let catalog = try loadCatalog()
        #expect(catalog.models.count == 33)

        for model in catalog.models {
            let command = CoreAIConversionPlanner.exportCommand(
                model: model,
                uvExecutableURL: URL(filePath: "/opt/homebrew/bin/uv"),
                repositoryURL: URL(filePath: "/tmp/coreai-models", directoryHint: .isDirectory),
                outputDirectoryURL: URL(filePath: "/tmp/exports", directoryHint: .isDirectory),
                precision: nil,
                overwrite: false
            )

            #expect(command.arguments.first == "run", "Missing uv run for \(model.id)")
            #expect(command.arguments.contains("--output-dir"), "Missing output directory for \(model.id)")
            #expect(command.arguments.last == "/tmp/exports", "Unexpected output argument for \(model.id)")
        }
    }

    @Test
    func utilityRecipesExposeOnlyTheirSupportedPrecisions() throws {
        let models = try loadCatalog().models
        let depth = try #require(models.first { $0.shortName == "depth-anything-3-small" })
        let clap = try #require(models.first { $0.shortName == "clap-htsat" })
        let yolos = try #require(models.first { $0.shortName == "yolos-tiny" })

        #expect(depth.supportedConversionPrecisions == [.float32])
        #expect(clap.supportedConversionPrecisions == [.float16, .float32])
        #expect(yolos.supportedConversionPrecisions == CoreAIConversionPrecision.allCases)
    }

    private func loadCatalog() throws -> AppleCoreAIModelCatalogDocument {
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = repository.appending(
            path: "CoreAILab/Resources/AppleModels/apple-coreai-models.json"
        )
        return try AppleCoreAIModelCatalog.decode(Data(contentsOf: catalogURL))
    }
}
