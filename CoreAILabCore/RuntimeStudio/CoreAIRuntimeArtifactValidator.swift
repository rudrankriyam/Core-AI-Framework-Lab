import Foundation

enum CoreAIRuntimeArtifactValidator {
    static func validate(
        _ url: URL,
        for adapter: CoreAIExperienceAdapter,
        context: CoreAIRuntimeRunContext
    ) throws {
        guard context.recipeProvenance.requiresArtifactFamilyValidation else {
            return
        }

        let expected = context.comparisonIdentity.modelIdentifier
        let detected = detectedModelIdentifier(
            at: url,
            adapter: adapter
        )
        guard let detected else {
            throw CoreAIRuntimeArtifactValidationError.familyCouldNotBeVerified(
                expectedModelIdentifier: expected
            )
        }
        guard detected == expected else {
            throw CoreAIRuntimeArtifactValidationError.modelFamilyMismatch(
                expectedModelIdentifier: expected,
                detectedModelIdentifier: detected
            )
        }
    }

    private static func detectedModelIdentifier(
        at url: URL,
        adapter: CoreAIExperienceAdapter
    ) -> String? {
        let candidates = artifactNames(at: url)
        let identifiers = Set(candidates.compactMap { name in
            modelIdentifier(for: name, adapter: adapter)
        })
        guard identifiers.count == 1 else { return nil }
        return identifiers.first
    }

    private static func artifactNames(at url: URL) -> [String] {
        var names = [url.lastPathComponent]
        let metadataURL = url.appending(path: "metadata.json")
        if let data = try? Data(contentsOf: metadataURL),
           let header = try? JSONDecoder().decode(
               CoreAIResourceBundleHeader.self,
               from: data
           ) {
            names.append(header.name)
        }
        return names
    }

    private static func modelIdentifier(
        for artifactName: String,
        adapter: CoreAIExperienceAdapter
    ) -> String? {
        let syntheticURL = URL(filePath: "/\(artifactName)")
        switch adapter {
        case .appleAudioTranscription:
            return AppleAudioExample(modelAssetURL: syntheticURL) == .wav2Vec2
                ? "wav2vec2-base"
                : nil
        case .appleDiffusion:
            switch AppleDiffusionExample(resourceBundleURL: syntheticURL) {
            case .stableDiffusion15:
                return "sd-1.5"
            case .stableDiffusion21:
                return "sd-2.1"
            case .stableDiffusion35:
                return "sd-3.5-medium"
            case .flux2Klein4B:
                return "flux2-klein-4b"
            case .exportedBundle:
                return nil
            }
        case .appleLanguage:
            return AppleLanguageExample(resourceBundleURL: syntheticURL) == .qwen3_0_6B
                ? "qwen3-0.6b"
                : nil
        case .appleObjectDetection:
            let normalized = artifactName.lowercased().replacing("_", with: "-")
            return normalized.contains("yolos-tiny") ? "yolos-tiny" : nil
        case .appleSegmentation:
            switch AppleSegmentationExample(resourceBundleURL: syntheticURL) {
            case .efficientSAM:
                return "efficient-sam-vitt"
            case .sam3:
                return "sam3"
            case nil:
                return nil
            }
        case .genericFunctionWorkbench:
            return nil
        }
    }
}
