import SwiftUI

struct AppleObjectDetectionHeaderView: View {
    let modelName: String?
    let imageName: String?
    let statusMessage: String
    let isBusy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("YOLOS Tiny", systemImage: "viewfinder")
                .font(.title2.bold())

            LabeledContent("Model", value: modelName ?? "Not imported")
            LabeledContent("Image", value: imageName ?? "Not selected")

            if isBusy {
                ProgressView(statusMessage)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .help("Uses Apple's YOLOS export recipe and CoreAIObjectDetection runtime.")
        .accessibilityElement(children: .contain)
    }
}
