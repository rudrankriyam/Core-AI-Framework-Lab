import SwiftUI

struct CoreAIRuntimeExperienceDestinationView: View {
    let mapping: CoreAIRecipeExperienceMapping
    let coordinator: CoreAIRunLifecycleCoordinator

    @ViewBuilder
    var body: some View {
        if !mapping.experience.platforms.contains(.current) {
            CoreAIRuntimeUnsupportedExperienceView(mapping: mapping)
        } else {
            switch mapping.experience.adapter {
            case .appleAudioTranscription:
                if let example = AppleAudioExample(
                    shortName: mapping.experience.modelIdentifier
                ) {
                    AppleAudioWorkspaceView(
                        example: example,
                        runContext: mapping.runContext,
                        runCoordinator: coordinator
                    )
                } else {
                    CoreAIRuntimeUnsupportedExperienceView(mapping: mapping)
                }
            case .appleDiffusion:
                if let example = AppleDiffusionExample(
                    shortName: mapping.experience.modelIdentifier
                ) {
                    AppleDiffusionWorkspaceView(
                        example: example,
                        runContext: mapping.runContext,
                        runCoordinator: coordinator
                    )
                } else {
                    CoreAIRuntimeUnsupportedExperienceView(mapping: mapping)
                }
            case .appleLanguage:
                if let example = AppleLanguageExample(
                    shortName: mapping.experience.modelIdentifier
                ) {
                    AppleLanguageWorkspaceView(
                        example: example,
                        runContext: mapping.runContext,
                        runCoordinator: coordinator
                    )
                } else {
                    CoreAIRuntimeUnsupportedExperienceView(mapping: mapping)
                }
            case .appleObjectDetection:
                if mapping.experience.modelIdentifier == "yolos-tiny" {
                    AppleObjectDetectionWorkspaceView(
                        runContext: mapping.runContext,
                        runCoordinator: coordinator
                    )
                } else {
                    CoreAIRuntimeUnsupportedExperienceView(mapping: mapping)
                }
            case .appleSegmentation:
                if let example = AppleSegmentationExample(
                    shortName: mapping.experience.modelIdentifier
                ) {
                    AppleSegmentationWorkspaceView(
                        example: example,
                        runContext: mapping.runContext,
                        runCoordinator: coordinator
                    )
                } else {
                    CoreAIRuntimeUnsupportedExperienceView(mapping: mapping)
                }
            case .genericFunctionWorkbench:
                CoreAIFunctionWorkbenchView(
                    runContext: mapping.runContext,
                    runCoordinator: coordinator
                )
            }
        }
    }
}
