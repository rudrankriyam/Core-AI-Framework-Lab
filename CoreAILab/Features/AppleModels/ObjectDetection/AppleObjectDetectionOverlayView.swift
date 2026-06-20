import SwiftUI

struct AppleObjectDetectionOverlayView: View {
    let imageSize: CGSize
    let detections: [AppleObjectDetection]

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / imageSize.width
            let scaleY = size.height / imageSize.height

            for detection in detections {
                let box = detection.boundingBox
                let scaledBox = CGRect(
                    x: box.minX * scaleX,
                    y: box.minY * scaleY,
                    width: box.width * scaleX,
                    height: box.height * scaleY
                )
                context.stroke(
                    Path(scaledBox),
                    with: .color(.orange),
                    lineWidth: 2
                )

                let confidence = detection.confidence.formatted(
                    .percent.precision(.fractionLength(0))
                )
                context.draw(
                    Text("\(detection.label) \(confidence)")
                        .font(.caption.bold())
                        .foregroundStyle(.orange),
                    at: CGPoint(x: scaledBox.minX + 4, y: scaledBox.minY + 4),
                    anchor: .topLeading
                )
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
