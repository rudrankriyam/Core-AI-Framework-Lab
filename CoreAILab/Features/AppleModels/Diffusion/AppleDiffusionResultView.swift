import SwiftUI

struct AppleDiffusionResultView: View {
    let result: AppleDiffusionResult?

    var body: some View {
        Section {
            if let result {
                Image(decorative: result.image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 12))
                    .accessibilityLabel("Locally generated diffusion image")
                LabeledContent(
                    "Inference",
                    value: "\(result.durationSeconds.formatted(.number.precision(.fractionLength(2)))) seconds"
                )
            } else {
                ContentUnavailableView(
                    "No Image Yet",
                    systemImage: "photo.badge.plus"
                )
            }
        } header: {
            Label("Generated Image", systemImage: "photo")
        }
    }
}
