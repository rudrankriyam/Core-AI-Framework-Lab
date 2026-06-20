import SwiftUI

struct AppleSegmentationQueryControlsView: View {
    @Bindable var workspace: AppleSegmentationWorkspaceModel

    var body: some View {
        Section(workspace.example.usesTextPrompt ? "Text Prompt" : "Point Prompt") {
            if workspace.example.usesTextPrompt {
                TextField(
                    "Object to segment",
                    text: $workspace.textPrompt,
                    axis: .vertical
                )
                .lineLimit(2...4)
                Text("SAM 3 uses the tokenizer bundled with Apple's exported resource folder.")
                    .foregroundStyle(.secondary)
            } else if workspace.sourceImage != nil {
                LabeledContent("Horizontal position") {
                    Text(workspace.pointX, format: .number.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                Slider(value: $workspace.pointX, in: 0...workspace.imageWidth)

                LabeledContent("Vertical position") {
                    Text(workspace.pointY, format: .number.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                Slider(value: $workspace.pointY, in: 0...workspace.imageHeight)

                Text("Coordinates are measured in pixels from the image's top-left corner.")
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    "Choose an Image",
                    systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
                    description: Text("Point controls appear after an image is loaded.")
                )
            }
        }
    }
}
