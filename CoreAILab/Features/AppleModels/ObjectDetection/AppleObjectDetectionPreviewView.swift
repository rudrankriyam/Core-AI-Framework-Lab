import SwiftUI

struct AppleObjectDetectionPreviewView: View {
    let image: CGImage
    let detections: [AppleObjectDetection]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .overlay {
                    AppleObjectDetectionOverlayView(
                        imageSize: CGSize(width: image.width, height: image.height),
                        detections: detections
                    )
                }
                .accessibilityLabel("Object detection source image")

            if !detections.isEmpty {
                Table(detections) {
                    TableColumn("Object", value: \.label)
                    TableColumn("Confidence") { detection in
                        Text(
                            detection.confidence,
                            format: .percent.precision(.fractionLength(1))
                        )
                    }
                    TableColumn("Bounds") { detection in
                        Text(boundsDescription(detection.boundingBox))
                            .font(.callout.monospaced())
                    }
                }
                .frame(minHeight: 180)
                .accessibilityLabel("Detected objects")
            }
        }
    }

    private func boundsDescription(_ bounds: CGRect) -> String {
        "x \(Int(bounds.minX)), y \(Int(bounds.minY)), w \(Int(bounds.width)), h \(Int(bounds.height))"
    }
}
