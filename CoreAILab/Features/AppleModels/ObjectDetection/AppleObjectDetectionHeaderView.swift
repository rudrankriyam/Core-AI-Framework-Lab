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

            Text("The first runnable Apple gallery model uses Apple's export recipe and CoreAIObjectDetection Swift package.")
                .foregroundStyle(.secondary)

            LabeledContent("Model", value: modelName ?? "Not imported")
            LabeledContent("Image", value: imageName ?? "Not selected")

            if isBusy {
                ProgressView(statusMessage)
                    .accessibilityAddTraits(.updatesFrequently)
            } else {
                Label(statusMessage, systemImage: "viewfinder")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
