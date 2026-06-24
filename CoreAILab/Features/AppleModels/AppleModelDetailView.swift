import SwiftUI

struct AppleModelDetailView: View {
    let model: AppleCoreAIModel
    let sourceRevision: String

    var body: some View {
        Form {
            Section {
                LabeledContent("Model") {
                    Text(model.huggingFaceID)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent(
                    "Platforms",
                    value: model.supportedPlatforms.map(\.rawValue).joined(separator: ", ")
                )
                if let computePrecision = model.computePrecision {
                    LabeledContent("Compute precision", value: computePrecision)
                }
                if let compression = model.compression {
                    LabeledContent("Compression", value: compression)
                }
                if let maximumContextLength = model.maximumContextLength {
                    LabeledContent("Maximum context", value: maximumContextLength.formatted())
                }
            } header: {
                Label(model.category.rawValue, systemImage: model.category.systemImage)
            }

            Section {
                Text(model.labRecommendedExportCommand)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .help(
                        "Run from the root of a local apple/coreai-models checkout, then import the exported asset."
                    )

                if let recipeURL = model.recipeURL(sourceRevision: sourceRevision) {
                    Link("Read the pinned Apple recipe", destination: recipeURL)
                }

                NavigationLink(
                    "Convert This Recipe",
                    value: AppleModelLibraryRoute.conversion(modelID: model.id)
                )
            } header: {
                Label("Export Recipe", systemImage: "terminal")
            }

            Section {
                Label(model.runtimeSupport.title, systemImage: "shippingbox")
                    .help(model.runtimeSupport.detail)

                if let productName = model.runtimeSupport.productName {
                    LabeledContent("Swift product", value: productName)
                }

                if model.runtimeSupport == .objectDetection, model.isRunnableInLab {
                    NavigationLink(
                        "Open Object Detection Playground",
                        value: AppleModelLibraryRoute.objectDetection
                    )
                }

                if let segmentationExample = model.segmentationExample {
                    if segmentationExample == .sam3 {
                        Label("Upstream license required", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help(
                                "Accept Meta's gated Hugging Face license and authenticate with the hf tool before export. Core AI Lab never reads or stores those credentials."
                            )
                    }
                    NavigationLink(
                        segmentationExample.playgroundButtonTitle,
                        value: AppleModelLibraryRoute.segmentation(segmentationExample)
                    )
                }

                if let languageExample = model.languageExample {
                    NavigationLink(
                        languageExample.playgroundButtonTitle,
                        value: AppleModelLibraryRoute.languageModel(languageExample)
                    )
                }

                if let diffusionExample = model.diffusionExample {
                    if diffusionExample == .stableDiffusion35 {
                        Label("Upstream license required", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help(
                                "Accept Stability AI's gated Hugging Face terms and authenticate with the hf tool before export. Core AI Lab never reads or stores those credentials."
                            )
                    }
                    NavigationLink(
                        diffusionExample.playgroundButtonTitle,
                        value: AppleModelLibraryRoute.diffusion(diffusionExample)
                    )
                }

                if let audioExample = model.audioExample {
                    NavigationLink(
                        audioExample.playgroundButtonTitle,
                        value: AppleModelLibraryRoute.audio(audioExample)
                    )
                }
            } header: {
                Label("Runtime Integration", systemImage: "play.rectangle")
            }

            Section {
                LabeledContent("Registry revision") {
                    Text(sourceRevision)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Recipe code", value: "Apple BSD-3-Clause")
                LabeledContent("Model weights", value: "Upstream license")
            } header: {
                Label("Provenance", systemImage: "checkmark.seal")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(model.shortName)
    }
}
