import SwiftUI

struct AppleSegmentationPreviewView: View {
    let image: CGImage?
    let result: AppleSegmentationResult?

    var body: some View {
        Section {
            if let image {
                Image(
                    image,
                    scale: 1,
                    label: Text("Image with generated segmentation masks")
                )
                .resizable()
                .scaledToFit()

                if let result {
                    LabeledContent("Segments", value: result.segmentCount, format: .number)
                    ForEach(result.scores.prefix(5).enumerated(), id: \.offset) { index, score in
                        LabeledContent("Score \(index + 1)") {
                            Text(score, format: .percent.precision(.fractionLength(1)))
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Image",
                    systemImage: "photo"
                )
            }
        } header: {
            Label("Result", systemImage: "square.stack.3d.up")
        }
    }
}
