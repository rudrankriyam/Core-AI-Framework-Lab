import Foundation
import Testing
@testable import CoreAILab

struct AppleCoreAIModelCatalogTests {
    @Test
    func pinnedCatalogContainsEveryUpstreamPreset() throws {
        let catalog = try loadCatalog()

        #expect(catalog.sourceRevision == "e358c8435679c904687f8070eb95150e36e4b76d")
        #expect(catalog.models.count == 33)
        #expect(Set(catalog.models.map(\.id)).count == 33)
        #expect(catalog.models.count(where: { $0.type == "llm" }) == 13)
        #expect(catalog.models.count(where: { $0.type == "diffusion" }) == 4)
        #expect(catalog.models.count(where: { $0.exportScript != nil }) == 16)
    }

    @Test
    func exportCommandsPreservePinnedRegistryDefaults() throws {
        let models = try loadCatalog().models
        let qwenMac = try #require(
            models.first {
                $0.shortName == "qwen3-0.6b" && $0.variant == "macOS"
            }
        )
        let qwenIOS = try #require(
            models.first {
                $0.shortName == "qwen3-0.6b" && $0.variant == "iOS"
            }
        )
        let stableDiffusion = try #require(
            models.first { $0.shortName == "sd-1.5" }
        )
        let yolosTiny = try #require(
            models.first { $0.shortName == "yolos-tiny" }
        )

        #expect(
            qwenMac.exportCommand
                == "uv run coreai.llm.export Qwen/Qwen3-0.6B --compression 4bit --compute-precision float16 --max-context-length 8192"
        )
        #expect(
            qwenIOS.exportCommand
                == "uv run coreai.llm.export Qwen/Qwen3-0.6B --compression-config models/qwen3/qwen3_0_6b_mixed_4bit_8bit.yaml --compute-precision float16 --max-context-length 4096 --platform iOS"
        )
        #expect(
            stableDiffusion.exportCommand
                == "uv run coreai.diffusion.export runwayml/stable-diffusion-v1-5 --compression none --compute-precision float16"
        )
        #expect(
            yolosTiny.labRecommendedExportCommand
                == "uv run models/yolo/export.py --model hustvl/yolos-tiny --dtype float16"
        )
    }

    @Test
    func catalogMapsAppleRuntimeProducts() throws {
        let models = try loadCatalog().models
        let yolosTiny = try #require(
            models.first { $0.shortName == "yolos-tiny" }
        )
        let qwen = try #require(
            models.first { $0.shortName == "qwen3-0.6b" }
        )
        let efficientSAM = try #require(
            models.first { $0.shortName == "efficient-sam-vitt" }
        )
        let sam3 = try #require(
            models.first { $0.shortName == "sam3" }
        )

        #expect(yolosTiny.runtimeSupport == .objectDetection)
        #expect(yolosTiny.runtimeSupport.productName == "CoreAIObjectDetection")
        #expect(yolosTiny.isRunnableInLab)

        let yolosBase = try #require(
            models.first { $0.shortName == "yolos-base" }
        )
        #expect(!yolosBase.isRunnableInLab)
        #expect(qwen.runtimeSupport == .languageModel)
        #expect(qwen.languageExample == .qwen3_0_6B)
        #expect(qwen.isRunnableInLab)
        #expect(efficientSAM.runtimeSupport == .segmentation)
        #expect(efficientSAM.segmentationExample == .efficientSAM)
        #expect(efficientSAM.isRunnableInLab)
        #expect(sam3.runtimeSupport == .segmentation)
        #expect(sam3.segmentationExample == .sam3)
        #expect(sam3.isRunnableInLab)
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
