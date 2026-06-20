import SwiftUI

struct AppleModelDetailView: View {
    let model: AppleCoreAIModel
    let sourceRevision: String

    var body: some View {
        Form {
            Section {
                LabeledContent("Model", value: model.huggingFaceID)
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

            Section("Export with Apple's recipe") {
                Text("Clone apple/coreai-models, run this command from its root, then import the resulting .aimodel or resource folder into the Lab.")
                    .foregroundStyle(.secondary)

                Text(model.labRecommendedExportCommand)
                    .font(.body.monospaced())
                    .textSelection(.enabled)

                if let recipeURL = model.recipeURL(sourceRevision: sourceRevision) {
                    Link("Read the pinned Apple recipe", destination: recipeURL)
                }
            }

            Section("Runtime integration") {
                Label(model.runtimeSupport.title, systemImage: "shippingbox")
                Text(model.runtimeSupport.detail)
                    .foregroundStyle(.secondary)

                if let productName = model.runtimeSupport.productName {
                    LabeledContent("Swift product", value: productName)
                }

                if model.runtimeSupport.isRunnableInLab {
                    NavigationLink(
                        "Open Object Detection Playground",
                        value: AppleModelLibraryRoute.objectDetection
                    )
                }
            }

            Section("Provenance") {
                LabeledContent("Registry revision") {
                    Text(sourceRevision)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                Text("The export recipe and Swift utilities use Apple's BSD-3-Clause repository. Downloaded model weights retain their original authors' licenses and are not redistributed by Core AI Lab.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(model.shortName)
    }
}
